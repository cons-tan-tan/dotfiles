#!/usr/bin/env python3

"""Measure and conservatively refine the matrix emitted by Hestia.

The current-run plan is deliberately only a guardrail. Historical telemetry is
the stable input intended for a future cost optimizer; failures here preserve
Hestia's original matrix byte-for-byte in terms of scheduled installables.
"""

from __future__ import annotations

import concurrent.futures
import json
import math
import os
import re
import shlex
import subprocess
import sys
import time
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from pathlib import Path

from ci_telemetry import (
    atomic_write_json,
    canonical_json,
    check_id,
    document,
    drv_id,
    job_identity,
    stable_hash,
)
from validate_hestia_matrix import require_env, validate_matrix

INSTALLABLE_PATTERN = re.compile(r"^(/nix/store/[0-9a-z]{32}-[^\s/]+\.drv)\^\*$")
PLANNED_DERIVATION_PATTERN = re.compile(
    r"^  (/nix/store/[0-9a-z]{32}-[^\s/]+\.drv)$", re.MULTILINE
)
ALGORITHM = "hestia-overlap"
ALGORITHM_VERSION = "1"


@dataclass(frozen=True)
class Candidate:
    rows: tuple[dict[str, object], ...]
    plan: frozenset[str]
    member_check_ids: frozenset[str]

    @property
    def names(self) -> tuple[str, ...]:
        return tuple(str(row["name"]) for row in self.rows)

    @property
    def os(self) -> tuple[str, ...]:
        labels = self.rows[0]["os"]
        assert isinstance(labels, list)
        return tuple(sorted({str(label) for label in labels}))

    @property
    def system(self) -> str:
        return str(self.rows[0]["system"])


def parse_float(name: str, default: str, *, minimum: float, maximum: float) -> float:
    raw = os.environ.get(name, default)
    try:
        value = float(raw)
    except ValueError as error:
        raise ValueError(f"{name} must be a number") from error
    if not minimum <= value <= maximum:
        raise ValueError(f"{name} must be between {minimum} and {maximum}")
    return value


def parse_int(name: str, default: str, *, minimum: int, maximum: int) -> int:
    raw = os.environ.get(name, default)
    if not re.fullmatch(r"[0-9]+", raw):
        raise ValueError(f"{name} must be an integer")
    value = int(raw)
    if not minimum <= value <= maximum:
        raise ValueError(f"{name} must be between {minimum} and {maximum}")
    return value


def installables(row: dict[str, object]) -> list[str]:
    raw = row["installables"]
    if not isinstance(raw, str):
        raise ValueError(f"invalid Hestia installables for {row.get('name')}")
    values = shlex.split(raw)
    if not values or not all(INSTALLABLE_PATTERN.fullmatch(value) for value in values):
        raise ValueError(f"invalid Hestia installables for {row.get('name')}")
    return values


def root_drv_paths(row: dict[str, object]) -> list[str]:
    return [
        INSTALLABLE_PATTERN.fullmatch(value).group(1) for value in installables(row)
    ]  # type: ignore[union-attr]


def all_root_installables(rows: Sequence[dict[str, object]]) -> list[str]:
    return sorted({value for row in rows for value in installables(row)})


def collect_missing_plan(
    rows: Sequence[dict[str, object]], timeout_seconds: int
) -> tuple[frozenset[str], int]:
    command = [
        "nix",
        "build",
        "--dry-run",
        "--json",
        "--no-link",
        "--log-format",
        "raw",
        *all_root_installables(rows),
    ]
    environment = os.environ.copy()
    environment["LC_ALL"] = "C"
    started = time.monotonic()
    result = subprocess.run(
        command,
        check=False,
        capture_output=True,
        text=True,
        timeout=timeout_seconds,
        env=environment,
    )
    duration_ms = round((time.monotonic() - started) * 1000)
    if result.returncode != 0:
        detail = result.stderr.strip().splitlines()
        suffix = f": {detail[-1]}" if detail else ""
        raise RuntimeError(f"Nix dry-run failed{suffix}")
    return frozenset(PLANNED_DERIVATION_PATTERN.findall(result.stderr)), duration_ms


def query_requisites(root_drv: str, timeout_seconds: int) -> frozenset[str]:
    result = subprocess.run(
        ["nix-store", "--query", "--requisites", root_drv],
        check=False,
        capture_output=True,
        text=True,
        timeout=timeout_seconds,
    )
    if result.returncode != 0:
        raise RuntimeError(f"could not query requisites for {root_drv}")
    return frozenset(
        line for line in result.stdout.splitlines() if line.endswith(".drv")
    )


def collect_group_plans(
    rows: Sequence[dict[str, object]],
    *,
    timeout_seconds: int,
    plan_provider: Callable[
        [Sequence[dict[str, object]], int], tuple[frozenset[str], int]
    ] = collect_missing_plan,
    closure_provider: Callable[[str, int], frozenset[str]] = query_requisites,
) -> tuple[list[frozenset[str]], frozenset[str], int, dict[str, frozenset[str]]]:
    missing, duration_ms = plan_provider(rows, timeout_seconds)
    roots = sorted({path for row in rows for path in root_drv_paths(row)})
    with concurrent.futures.ThreadPoolExecutor(
        max_workers=min(2, len(roots))
    ) as executor:
        futures = {
            root: executor.submit(closure_provider, root, timeout_seconds)
            for root in roots
        }
        root_plans = {
            root: future.result() & missing for root, future in futures.items()
        }
    return (
        [
            frozenset().union(*(root_plans[root] for root in root_drv_paths(row)))
            for row in rows
        ],
        missing,
        duration_ms,
        root_plans,
    )


def pair_score(
    left: Candidate,
    right: Candidate,
    *,
    baseline_critical_path: int,
    critical_path_slack: float,
    min_shared_derivations: int,
    min_shared_ratio: float,
) -> tuple[int, float, int] | None:
    if left.system != right.system or left.os != right.os:
        return None
    shared = left.plan & right.plan
    smaller_plan = min(len(left.plan), len(right.plan))
    if smaller_plan == 0 or len(shared) < min_shared_derivations:
        return None
    shared_ratio = len(shared) / smaller_plan
    if shared_ratio < min_shared_ratio:
        return None
    merged_size = len(left.plan | right.plan)
    allowed_size = math.ceil(baseline_critical_path * (1 + critical_path_slack))
    if merged_size > allowed_size:
        return None
    return (len(shared), shared_ratio, -merged_size)


def optimize_candidates(
    candidates: Sequence[Candidate],
    *,
    critical_path_slack: float,
    min_shared_derivations: int,
    min_shared_ratio: float,
) -> list[Candidate]:
    optimized = sorted(
        candidates,
        key=lambda candidate: (
            candidate.system,
            candidate.os,
            tuple(sorted(candidate.member_check_ids)),
        ),
    )
    baseline = max((len(candidate.plan) for candidate in optimized), default=0)
    if baseline == 0:
        return optimized
    while True:
        best: tuple[tuple[int, float, int], int, int] | None = None
        for left_index, left in enumerate(optimized):
            for right_index in range(left_index + 1, len(optimized)):
                score = pair_score(
                    left,
                    optimized[right_index],
                    baseline_critical_path=baseline,
                    critical_path_slack=critical_path_slack,
                    min_shared_derivations=min_shared_derivations,
                    min_shared_ratio=min_shared_ratio,
                )
                if score is not None and (best is None or score > best[0]):
                    best = (score, left_index, right_index)
        if best is None:
            return optimized
        _, left_index, right_index = best
        left = optimized[left_index]
        right = optimized[right_index]
        optimized[left_index] = Candidate(
            rows=left.rows + right.rows,
            plan=left.plan | right.plan,
            member_check_ids=left.member_check_ids | right.member_check_ids,
        )
        del optimized[right_index]


def inferred_check_ids(row: dict[str, object], attr_prefix: str) -> frozenset[str]:
    system = str(row["system"])
    attr = row.get("attr")
    full_attr = (
        str(attr) if isinstance(attr, str) and attr else f"{attr_prefix}.{row['name']}"
    )
    return frozenset({check_id(system, full_attr)})


def candidate_to_row(candidate: Candidate) -> dict[str, object]:
    values = sorted({value for row in candidate.rows for value in installables(row)})
    result = dict(candidate.rows[0])
    result["name"] = "+".join(candidate.names)
    result["installables"] = " ".join(values)
    job_id, telemetry_key = job_identity(
        system=candidate.system,
        runner_labels=candidate.os,
        member_check_ids=candidate.member_check_ids,
    )
    result["jobId"] = job_id
    result["telemetryKey"] = telemetry_key
    return result


def optimize_rows(
    rows: Sequence[dict[str, object]],
    plans: Sequence[frozenset[str]],
    *,
    critical_path_slack: float,
    min_shared_derivations: int,
    min_shared_ratio: float,
    member_ids: Sequence[frozenset[str]] | None = None,
    attr_prefix: str = "lib.hestiaJobs.ci.x86_64-linux",
) -> list[dict[str, object]]:
    if len(rows) != len(plans):
        raise ValueError("Hestia rows and Nix plans have different lengths")
    if member_ids is None:
        member_ids = [inferred_check_ids(row, attr_prefix) for row in rows]
    candidates = [
        Candidate(rows=(row,), plan=plan, member_check_ids=ids)
        for row, plan, ids in zip(rows, plans, member_ids, strict=True)
    ]
    return [
        candidate_to_row(candidate)
        for candidate in optimize_candidates(
            candidates,
            critical_path_slack=critical_path_slack,
            min_shared_derivations=min_shared_derivations,
            min_shared_ratio=min_shared_ratio,
        )
    ]


def read_eval_records(path: Path) -> list[dict[str, object]]:
    records: list[dict[str, object]] = []
    with path.open(encoding="utf-8") as source:
        for number, line in enumerate(source, 1):
            try:
                value = json.loads(line)
            except json.JSONDecodeError as error:
                raise ValueError(
                    f"invalid captured evaluation line {number}"
                ) from error
            if not isinstance(value, dict):
                raise ValueError(f"captured evaluation line {number} is not an object")
            if isinstance(value.get("attr"), str) and isinstance(
                value.get("drvPath"), str
            ):
                records.append(value)
    return records


def full_attr_path(raw_attr: str, prefix: str) -> str:
    return (
        raw_attr
        if raw_attr == prefix or raw_attr.startswith(f"{prefix}.")
        else f"{prefix}.{raw_attr}"
    )


def record_group(record: dict[str, object]) -> str | None:
    meta = record.get("meta")
    if not isinstance(meta, dict):
        return None
    hestia = meta.get("hestia")
    if not isinstance(hestia, dict):
        return None
    group = hestia.get("group")
    return group if isinstance(group, str) and group else None


def record_runner_labels(record: dict[str, object]) -> list[str]:
    meta = record.get("meta")
    hestia = meta.get("hestia") if isinstance(meta, dict) else None
    raw = hestia.get("os") if isinstance(hestia, dict) else None
    if isinstance(raw, str) and raw:
        return [raw]
    if isinstance(raw, list) and all(isinstance(label, str) and label for label in raw):
        return sorted(set(raw))
    return []


def member_ids_for_rows(
    rows: Sequence[dict[str, object]], records: Sequence[dict[str, object]], prefix: str
) -> tuple[list[frozenset[str]], list[dict[str, object]], bool]:
    root_to_row: dict[str, int] = {}
    for index, row in enumerate(rows):
        for root in root_drv_paths(row):
            if root in root_to_row:
                raise ValueError("Hestia roots occur in more than one static row")
            root_to_row[root] = index
    members = [set() for _ in rows]
    checks: list[dict[str, object]] = []
    manifest_complete = True
    for record in records:
        raw_attr = str(record["attr"])
        drv_path = str(record["drvPath"])
        system = str(record.get("system") or require_env("SYSTEM"))
        attr_path = full_attr_path(raw_attr, prefix)
        identity = check_id(system, attr_path)
        scheduled_row = root_to_row.get(drv_path)
        if scheduled_row is not None:
            members[scheduled_row].add(identity)
            runner_labels = sorted(str(label) for label in rows[scheduled_row]["os"])
            selection = "scheduled"
        else:
            runner_labels = record_runner_labels(record)
            # A successful Hestia matrix step has already applied its cache
            # filter. Every valid evaluated root absent from the scheduled
            # matrix was therefore filtered, regardless of whether a specific
            # nix-eval-jobs release populated its isCached field.
            selection = "cached_filtered"
        checks.append(
            {
                "check_id": identity,
                "attr_path": attr_path,
                "display_name": raw_attr.rsplit(".", 1)[-1],
                "drv_id": drv_id(drv_path),
                "drv_path": drv_path,
                "system": system,
                "runner_labels": runner_labels,
                "static_affinity_group": record_group(record),
                "selection": selection,
                "plan": {"status": "not_observed", "dependency_drv_ids": []},
            }
        )
    for index, row in enumerate(rows):
        if not members[index]:
            manifest_complete = False
            base_identity = next(iter(inferred_check_ids(row, prefix)))
            base_attr = base_identity.split(":", 1)[1]
            roots = sorted(root_drv_paths(row))
            identities = frozenset(
                check_id(
                    str(row["system"]),
                    base_attr
                    if len(roots) == 1
                    else f"{base_attr}.__unknown_root_{root_index}",
                )
                for root_index, _root in enumerate(roots)
            )
            members[index].update(identities)
            for identity, drv_path in zip(sorted(identities), roots, strict=True):
                attr_path = identity.split(":", 1)[1]
                checks.append(
                    {
                        "check_id": identity,
                        "attr_path": attr_path,
                        "display_name": attr_path.rsplit(".", 1)[-1],
                        "drv_id": drv_id(drv_path),
                        "drv_path": drv_path,
                        "system": str(row["system"]),
                        "runner_labels": sorted(str(label) for label in row["os"]),
                        "static_affinity_group": str(row["name"]),
                        "selection": "unknown",
                        "plan": {
                            "status": "not_observed",
                            "dependency_drv_ids": [],
                        },
                    }
                )
    return (
        [frozenset(group) for group in members],
        sorted(checks, key=lambda item: str(item["check_id"])),
        manifest_complete,
    )


def nix_version() -> str:
    try:
        result = subprocess.run(
            ["nix", "--version"],
            check=False,
            capture_output=True,
            text=True,
            timeout=5,
        )
    except (OSError, subprocess.TimeoutExpired):
        return "unknown"
    return result.stdout.strip() if result.returncode == 0 else "unknown"


def decision_jobs(
    optimized_rows: Sequence[dict[str, object]],
    checks: Sequence[dict[str, object]],
    plans_by_check: dict[str, frozenset[str]],
) -> list[dict[str, object]]:
    result: list[dict[str, object]] = []
    check_by_id = {str(item["check_id"]): item for item in checks}
    for row in optimized_rows:
        job_id = str(row["jobId"])
        member_ids = sorted(
            identity
            for identity, item in check_by_id.items()
            if str(item["drv_path"]) in root_drv_paths(row)
        )
        if not member_ids:
            member_ids = sorted(
                inferred_check_ids(row, "lib.hestiaJobs.ci." + str(row["system"]))
            )
        planned = frozenset().union(
            *(plans_by_check.get(identity, frozenset()) for identity in member_ids)
        )
        result.append(
            {
                "job_id": job_id,
                "telemetry_key": str(row["telemetryKey"]),
                "name": str(row["name"]),
                "system": str(row["system"]),
                "runner_labels": sorted(str(label) for label in row["os"]),
                "member_check_ids": member_ids,
                "root_drv_ids": sorted(drv_id(path) for path in root_drv_paths(row)),
                "planned_drv_ids": sorted(drv_id(path) for path in planned),
            }
        )
    return sorted(result, key=lambda item: str(item["job_id"]))


def write_summary(
    rows: Sequence[dict[str, object]],
    optimized: Sequence[dict[str, object]],
    plans: Sequence[frozenset[str]],
    status: str,
) -> None:
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if not path:
        return
    lines = [
        "### Hestia matrix optimization",
        "",
        f"Status: `{status}`; static groups: {len(rows)}; build jobs: {len(optimized)}.",
        "",
        "| Static group | Planned derivations |",
        "| --- | ---: |",
        *(
            f"| `{row['name']}` | {len(plan)} |"
            for row, plan in zip(rows, plans, strict=True)
        ),
        "",
    ]
    with Path(path).open("a", encoding="utf-8") as output:
        output.write("\n".join(lines))


def emit_matrix(matrix: dict[str, object]) -> None:
    compact = json.dumps(matrix, ensure_ascii=False, separators=(",", ":"))
    with Path(require_env("GITHUB_OUTPUT")).open("a", encoding="utf-8") as output:
        output.write(f"matrix={compact}\n")


def main() -> None:
    raw_matrix = validate_matrix(
        require_env("HESTIA_MATRIX"),
        require_env("HESTIA_ANY_JOBS"),
        require_env("SYSTEM"),
    )
    matrix = json.loads(raw_matrix)
    rows = matrix["include"]
    prefix = os.environ.get(
        "TELEMETRY_ATTR_PREFIX", f"lib.hestiaJobs.ci.{require_env('SYSTEM')}"
    )
    telemetry_path = Path(require_env("CI_TELEMETRY_LANE"))
    parameters = {
        "critical_path_slack": parse_float(
            "MATRIX_OPTIMIZER_CRITICAL_PATH_SLACK", "0.05", minimum=0, maximum=1
        ),
        "min_shared_derivations": parse_int(
            "MATRIX_OPTIMIZER_MIN_SHARED_DERIVATIONS", "20", minimum=1, maximum=100_000
        ),
        "min_shared_ratio": parse_float(
            "MATRIX_OPTIMIZER_MIN_SHARED_RATIO", "0.25", minimum=0, maximum=1
        ),
    }
    timeout = parse_int(
        "MATRIX_OPTIMIZER_DRY_RUN_TIMEOUT_SECONDS", "30", minimum=1, maximum=300
    )
    capture_path = Path(require_env("HESTIA_EVAL_CAPTURE"))
    records = read_eval_records(capture_path)
    members, checks, manifest_complete = member_ids_for_rows(rows, records, prefix)
    plans = [frozenset() for _ in rows]
    root_plan: dict[str, frozenset[str]] = {}
    missing: frozenset[str] = frozenset()
    duration_ms = 0
    status = "not_needed" if len(rows) < 2 else "unchanged"
    reason: str | None = None
    plan_status = "success"
    collection_status = "complete"

    try:
        if rows:
            plans, missing, duration_ms, root_plan = collect_group_plans(
                rows, timeout_seconds=timeout
            )
        if manifest_complete:
            optimized_rows = optimize_rows(
                rows,
                plans,
                critical_path_slack=float(parameters["critical_path_slack"]),
                min_shared_derivations=int(parameters["min_shared_derivations"]),
                min_shared_ratio=float(parameters["min_shared_ratio"]),
                member_ids=members,
                attr_prefix=prefix,
            )
            if len(optimized_rows) < len(rows):
                status = "optimized"
        else:
            reason = "manifest_membership_missing"
            collection_status = "partial"
            status = "fallback"
            optimized_rows = optimize_rows(
                rows,
                plans,
                critical_path_slack=0,
                min_shared_derivations=100_000,
                min_shared_ratio=1,
                member_ids=members,
                attr_prefix=prefix,
            )
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        timed_out = isinstance(error, subprocess.TimeoutExpired)
        reason = "plan_timeout" if timed_out else "plan_collection_failed"
        plan_status = "timeout" if timed_out else "failed"
        collection_status = "partial"
        status = "fallback"
        print(f"::warning::Hestia matrix optimization skipped: {error}")
        optimized_rows = optimize_rows(
            rows,
            plans,
            critical_path_slack=0,
            min_shared_derivations=100_000,
            min_shared_ratio=1,
            member_ids=members,
            attr_prefix=prefix,
        )

    plans_by_check: dict[str, frozenset[str]] = {}
    for item in checks:
        identity = str(item["check_id"])
        plan = root_plan.get(str(item["drv_path"]), frozenset())
        if item["selection"] == "scheduled":
            item["plan"] = {
                "status": plan_status,
                "dependency_drv_ids": sorted(drv_id(path) for path in plan),
            }
        plans_by_check[identity] = plan

    static_groups = []
    for row, plan, member in zip(rows, plans, members, strict=True):
        static_groups.append(
            {
                "name": str(row["name"]),
                "system": str(row["system"]),
                "runner_labels": sorted(str(label) for label in row["os"]),
                "member_check_ids": sorted(member),
                "root_drv_ids": sorted(drv_id(path) for path in root_drv_paths(row)),
                "plan": {
                    "status": plan_status,
                    "dependency_drv_ids": sorted(drv_id(path) for path in plan),
                },
            }
        )

    jobs = decision_jobs(optimized_rows, checks, plans_by_check)
    lane = document(
        "lane",
        require_env("SYSTEM"),
        {
            "workflow_job": {
                "role": "system-evaluate",
                "runner_name": require_env("TELEMETRY_RUNNER_NAME"),
            },
            "collection_status": collection_status,
            "source": {
                "hestia_version": os.environ.get("HESTIA_VERSION", "unknown"),
                "manifest_version": os.environ.get(
                    "HESTIA_MANIFEST_VERSION", "unknown"
                ),
                "nix_version": nix_version(),
                "plan_method": "single-dry-run-and-store-requisites-v1",
                "plan_duration_ms": duration_ms,
            },
            "derivations": [
                {"drv_id": drv_id(path), "drv_path": path} for path in sorted(missing)
            ],
            "checks": checks,
            "static_groups": static_groups,
            "decision": {
                "algorithm": ALGORITHM,
                "algorithm_version": ALGORITHM_VERSION,
                "status": status,
                "reason_code": reason,
                "parameters": parameters,
                "input_fingerprint": stable_hash(
                    [
                        canonical_json(matrix),
                        *sorted(item["check_id"] for item in checks),
                    ]
                ),
                "jobs": jobs,
            },
        },
    )
    atomic_write_json(telemetry_path, lane)
    write_summary(rows, optimized_rows, plans, status)
    emit_matrix({"include": optimized_rows})


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
