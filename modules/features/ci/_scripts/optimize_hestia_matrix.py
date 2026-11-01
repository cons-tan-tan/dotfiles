#!/usr/bin/env python3

"""Merge Hestia groups using only the current run's uncached derivations."""

from __future__ import annotations

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

from validate_hestia_matrix import (
    require_env,
    validate_conservation,
    validate_matrix,
)

INSTALLABLE_PATTERN = re.compile(r"^(/nix/store/[0-9a-z]{32}-[^\s/]+\.drv)\^\*$")
PLANNED_DERIVATION_PATTERN = re.compile(
    r"^  (/nix/store/[0-9a-z]{32}-[^\s/]+\.drv)$", re.MULTILINE
)


@dataclass(frozen=True)
class Candidate:
    rows: tuple[dict[str, object], ...]
    plan: frozenset[str]

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


def collect_missing_plan(
    rows: Sequence[dict[str, object]], timeout_seconds: float
) -> frozenset[str]:
    command = [
        "nix",
        "build",
        "--dry-run",
        "--json",
        "--no-link",
        "--log-format",
        "raw",
        *sorted({value for row in rows for value in installables(row)}),
    ]
    environment = os.environ.copy()
    environment["LC_ALL"] = "C"
    result = subprocess.run(
        command,
        check=False,
        capture_output=True,
        text=True,
        timeout=timeout_seconds,
        env=environment,
    )
    if result.returncode != 0:
        detail = result.stderr.strip().splitlines()
        suffix = f": {detail[-1]}" if detail else ""
        raise RuntimeError(f"Nix dry-run failed{suffix}")
    return frozenset(PLANNED_DERIVATION_PATTERN.findall(result.stderr))


def query_requisites(roots: Sequence[str], timeout_seconds: float) -> frozenset[str]:
    result = subprocess.run(
        ["nix-store", "--query", "--requisites", *roots],
        check=False,
        capture_output=True,
        text=True,
        timeout=timeout_seconds,
    )
    if result.returncode != 0:
        raise RuntimeError("could not query group requisites")
    return frozenset(
        line for line in result.stdout.splitlines() if line.endswith(".drv")
    )


def has_compatible_groups(rows: Sequence[dict[str, object]]) -> bool:
    seen = set()
    for row in rows:
        key = (str(row["system"]), tuple(sorted(row["os"])))
        if key in seen:
            return True
        seen.add(key)
    return False


def collect_group_plans(
    rows: Sequence[dict[str, object]],
    *,
    timeout_seconds: int,
    min_shared_derivations: int,
    plan_provider: Callable[
        [Sequence[dict[str, object]], float], frozenset[str]
    ] = collect_missing_plan,
    closure_provider: Callable[
        [Sequence[str], float], frozenset[str]
    ] = query_requisites,
) -> list[frozenset[str]] | None:
    if not has_compatible_groups(rows):
        return None

    deadline = time.monotonic() + timeout_seconds

    def remaining() -> float:
        seconds = deadline - time.monotonic()
        if seconds <= 0:
            raise subprocess.TimeoutExpired("Hestia matrix planning", timeout_seconds)
        return seconds

    missing = plan_provider(rows, remaining())
    remaining()
    if len(missing) < min_shared_derivations:
        # No pair can reach the shared-work threshold. Do not label unqueried
        # group plans as empty: they may still contain uncached derivations.
        return None

    # There are at most five groups per system. One multi-root query per group
    # avoids repeated closure scans and needs no executor to drain on failure.
    plans = []
    for row in rows:
        closure = closure_provider(sorted(root_drv_paths(row)), remaining())
        remaining()
        plans.append(closure & missing)
    return plans


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
    # This bounds derivation count, not elapsed time; a single derivation can
    # cost more than many others. Keep the count guard when relaxing overlap.
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
            candidate.names,
            tuple(sorted(root_drv_paths(candidate.rows[0]))),
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
        )
        del optimized[right_index]


def candidate_to_row(candidate: Candidate) -> dict[str, object]:
    values = sorted({value for row in candidate.rows for value in installables(row)})
    result = dict(candidate.rows[0])
    result["name"] = "+".join(candidate.names)
    result["installables"] = " ".join(values)
    return result


def optimize_rows(
    rows: Sequence[dict[str, object]],
    plans: Sequence[frozenset[str]],
    *,
    critical_path_slack: float,
    min_shared_derivations: int,
    min_shared_ratio: float,
) -> list[dict[str, object]]:
    if len(rows) != len(plans):
        raise ValueError("Hestia rows and Nix plans have different lengths")
    candidates = [
        Candidate(rows=(row,), plan=plan) for row, plan in zip(rows, plans, strict=True)
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


def write_summary(
    rows: Sequence[dict[str, object]],
    optimized: Sequence[dict[str, object]],
    plans: Sequence[frozenset[str]] | None,
    status: str,
    duration_ms: int,
) -> None:
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if not path:
        return
    lines = [
        "### Hestia matrix optimization",
        "",
        f"Status: {status}; static groups: {len(rows)}; build jobs: {len(optimized)}.",
        f"Planning and grouping: {duration_ms} ms (including closure queries).",
        "",
    ]
    if plans is not None:
        lines += [
            "| Static group | Planned derivations |",
            "| --- | ---: |",
            *(
                f"| {row['name']} | {len(plan)} |"
                for row, plan in zip(rows, plans, strict=True)
            ),
            "",
        ]
    with Path(path).open("a", encoding="utf-8") as output:
        output.write("\n".join(lines))


def main() -> None:
    raw_matrix = validate_matrix(
        require_env("HESTIA_MATRIX"),
        require_env("HESTIA_ANY_JOBS"),
        require_env("SYSTEM"),
    )
    rows = json.loads(raw_matrix)["include"]
    parameters = {
        "critical_path_slack": parse_float(
            "MATRIX_OPTIMIZER_CRITICAL_PATH_SLACK", "0.05", minimum=0, maximum=1
        ),
        "min_shared_derivations": parse_int(
            "MATRIX_OPTIMIZER_MIN_SHARED_DERIVATIONS", "1", minimum=1, maximum=100_000
        ),
        "min_shared_ratio": parse_float(
            "MATRIX_OPTIMIZER_MIN_SHARED_RATIO", "0.25", minimum=0, maximum=1
        ),
    }
    timeout = parse_int(
        "MATRIX_OPTIMIZER_DRY_RUN_TIMEOUT_SECONDS", "30", minimum=1, maximum=300
    )
    # Fallback returns the original rows directly, independent of merge rules.
    optimized_rows = rows
    plans = None
    status = "not_needed"
    started = time.monotonic()
    try:
        plans = collect_group_plans(
            rows,
            timeout_seconds=timeout,
            min_shared_derivations=int(parameters["min_shared_derivations"]),
        )
        if plans is not None:
            optimized_rows = optimize_rows(rows, plans, **parameters)
            status = "optimized" if len(optimized_rows) < len(rows) else "unchanged"
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        status = "fallback"
        print(f"::warning::Hestia matrix optimization skipped: {error}")

    duration_ms = round((time.monotonic() - started) * 1000)
    matrix = json.dumps(
        {"include": optimized_rows}, ensure_ascii=False, separators=(",", ":")
    )
    validate_conservation(raw_matrix, matrix)
    with Path(require_env("GITHUB_OUTPUT")).open("a", encoding="utf-8") as output:
        output.write(f"matrix={matrix}\n")
    write_summary(rows, optimized_rows, plans, status, duration_ms)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
