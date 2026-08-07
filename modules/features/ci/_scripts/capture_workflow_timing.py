#!/usr/bin/env python3

"""Capture authoritative GitHub job timing for one completed source run."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

from ci_telemetry import atomic_write_json, read_document

COMMIT_PATTERN = re.compile(r"^[0-9a-f]{40}$")
REPOSITORY_PATTERN = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")


def require_mapping(value: object, label: str) -> dict[str, object]:
    if not isinstance(value, dict):
        raise ValueError(f"invalid {label}")
    return value


def require_string(value: object, label: str) -> str:
    if not isinstance(value, str) or not value:
        raise ValueError(f"invalid {label}")
    return value


def semantic_identity(
    *, role: object, system: object, runner_name: object, telemetry_key: object = None
) -> dict[str, object]:
    normalized_role = require_string(role, "workflow job role")
    if normalized_role not in {"flake-eval", "system-evaluate", "system-build"}:
        raise ValueError("invalid workflow job role")
    normalized_key = telemetry_key
    if normalized_role == "system-build":
        if (
            not isinstance(normalized_key, str)
            or re.fullmatch(r"[0-9a-f]{20}", normalized_key) is None
        ):
            raise ValueError("invalid workflow job telemetry key")
    elif normalized_key is not None:
        raise ValueError("unexpected workflow job telemetry key")
    return {
        "role": normalized_role,
        "system": require_string(system, "workflow job system"),
        "telemetry_key": normalized_key,
        "runner_name": require_string(runner_name, "workflow job runner name"),
    }


def load_workflow_identities(
    root: Path,
    *,
    repository: str,
    run_id: str,
    run_attempt: int,
    commit_sha: str,
) -> list[dict[str, object]]:
    index = require_mapping(json.loads((root / "index.json").read_text()), "run index")
    source = require_mapping(index.get("source"), "run source")
    if (
        source.get("repository") != repository
        or str(source.get("run_id")) != run_id
        or source.get("run_attempt") != run_attempt
        or source.get("head_sha") != commit_sha
    ):
        raise ValueError("workflow identities belong to another run")
    raw_flake_jobs = index.get("workflow_jobs")
    if raw_flake_jobs is None:
        return []
    if not isinstance(raw_flake_jobs, list) or not raw_flake_jobs:
        raise ValueError("run telemetry has invalid workflow jobs")
    identities = [
        semantic_identity(
            role=require_mapping(item, "workflow job").get("role"),
            system=require_mapping(item, "workflow job").get("system"),
            runner_name=require_mapping(item, "workflow job").get("runner_name"),
        )
        for item in raw_flake_jobs
    ]
    systems = index.get("systems")
    if not isinstance(systems, list):
        raise ValueError("run index has no systems")
    for raw_entry in systems:
        entry = require_mapping(raw_entry, "system entry")
        path = require_string(entry.get("bundle_path"), "system bundle path")
        bundle = read_document(root / path, "bundle")
        bundle_data = require_mapping(bundle.get("data"), "bundle data")
        lane = require_mapping(bundle_data.get("lane"), "lane telemetry")
        lane_run = require_mapping(lane.get("run"), "lane run")
        lane_data = require_mapping(lane.get("data"), "lane data")
        lane_identity = require_mapping(
            lane_data.get("workflow_job"), "lane workflow job"
        )
        identities.append(
            semantic_identity(
                role=lane_identity.get("role"),
                system=lane_run.get("system"),
                runner_name=lane_identity.get("runner_name"),
            )
        )
        jobs = bundle_data.get("jobs")
        if not isinstance(jobs, list):
            raise ValueError("bundle has no jobs")
        for raw_job in jobs:
            job = require_mapping(raw_job, "job telemetry")
            job_run = require_mapping(job.get("run"), "job run")
            job_data = require_mapping(job.get("data"), "job data")
            job_identity = require_mapping(
                job_data.get("workflow_job"), "build workflow job"
            )
            identities.append(
                semantic_identity(
                    role=job_identity.get("role"),
                    system=job_run.get("system"),
                    runner_name=job_identity.get("runner_name"),
                    telemetry_key=job_data.get("telemetry_key"),
                )
            )
    keys = [
        (identity["role"], identity["system"], identity["telemetry_key"])
        for identity in identities
    ]
    runner_names = [str(identity["runner_name"]) for identity in identities]
    if len(keys) != len(set(keys)):
        raise ValueError("duplicate workflow job identity")
    if len(runner_names) != len(set(runner_names)):
        raise ValueError("duplicate workflow job runner name")
    return sorted(
        identities,
        key=lambda item: (
            str(item["role"]),
            str(item["system"]),
            str(item["telemetry_key"] or ""),
        ),
    )


def normalize(
    raw: object,
    *,
    repository: str,
    run_id: str,
    run_attempt: int,
    identities: list[dict[str, object]] | None = None,
) -> dict[str, object]:
    if not isinstance(raw, dict):
        raise ValueError("invalid GitHub workflow timing response")
    jobs = raw.get("jobs")
    if raw.get("name") != "CI" or not isinstance(jobs, list):
        raise ValueError("unexpected GitHub workflow timing response")
    head_sha = require_string(raw.get("headSha"), "workflow commit")
    if COMMIT_PATTERN.fullmatch(head_sha) is None:
        raise ValueError("invalid workflow commit")
    if raw.get("attempt") != run_attempt:
        raise ValueError("workflow timing belongs to another attempt")
    if raw.get("conclusion") != "success":
        raise ValueError("source workflow was not successful")

    normalized: list[dict[str, object]] = []
    if identities:
        by_runner: dict[str, dict[str, object]] = {}
        for raw_job in jobs:
            job = require_mapping(raw_job, "GitHub workflow job")
            if job.get("runnerName") is None and job.get("conclusion") == "skipped":
                continue
            runner_name = require_string(job.get("runnerName"), "job runner name")
            if runner_name in by_runner:
                raise ValueError("duplicate GitHub workflow job runner name")
            by_runner[runner_name] = job
        for identity in identities:
            runner_name = require_string(
                identity.get("runner_name"), "workflow job runner name"
            )
            job = require_mapping(
                by_runner.get(runner_name), f"workflow job on runner {runner_name}"
            )
            normalized.append(
                {
                    **identity,
                    "started_at": require_string(job.get("startedAt"), "job start"),
                    "completed_at": require_string(
                        job.get("completedAt"), "job completion"
                    ),
                    "conclusion": require_string(
                        job.get("conclusion"), "job conclusion"
                    ),
                }
            )
        schema_version = 2
    else:
        seen: set[str] = set()
        for raw_job in jobs:
            job = require_mapping(raw_job, "GitHub workflow job")
            name = require_string(job.get("name"), "workflow job name")
            if name in seen:
                raise ValueError("duplicate GitHub workflow job name")
            seen.add(name)
            normalized.append(
                {
                    "name": name,
                    "started_at": require_string(job.get("startedAt"), "job start"),
                    "completed_at": require_string(
                        job.get("completedAt"), "job completion"
                    ),
                    "conclusion": require_string(
                        job.get("conclusion"), "job conclusion"
                    ),
                }
            )
        schema_version = 1
    return {
        "schema_version": schema_version,
        "document_type": "workflow_timing",
        "repository": repository,
        "run_id": run_id,
        "run_attempt": run_attempt,
        "commit_sha": head_sha,
        "started_at": require_string(raw.get("startedAt"), "workflow start"),
        "completed_at": require_string(raw.get("updatedAt"), "workflow completion"),
        "jobs": normalized,
    }


def github_jobs(
    repository: str, run_id: str, run_attempt: int, *, timeout: float
) -> list[dict[str, object]]:
    jobs: list[dict[str, object]] = []
    for page in range(1, 11):
        result = subprocess.run(
            [
                "gh",
                "api",
                "--method",
                "GET",
                f"/repos/{repository}/actions/runs/{run_id}/attempts/{run_attempt}/jobs?per_page=100&page={page}",
            ],
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        if result.returncode != 0:
            detail = result.stderr.strip().splitlines()
            suffix = f": {detail[-1]}" if detail else ""
            raise RuntimeError(f"could not read source workflow jobs{suffix}")
        response = require_mapping(json.loads(result.stdout), "GitHub jobs response")
        raw_jobs = response.get("jobs")
        if not isinstance(raw_jobs, list):
            raise ValueError("GitHub jobs response has no jobs")
        for raw_job in raw_jobs:
            job = require_mapping(raw_job, "GitHub workflow job")
            jobs.append(
                {
                    "name": job.get("name"),
                    "runnerName": job.get("runner_name"),
                    "startedAt": job.get("started_at"),
                    "completedAt": job.get("completed_at"),
                    "conclusion": job.get("conclusion"),
                }
            )
        if len(raw_jobs) < 100:
            return jobs
    raise ValueError("GitHub workflow has too many jobs")


def capture(
    repository: str,
    run_id: str,
    run_attempt: int,
    *,
    telemetry_root: Path | None = None,
    timeout: float = 60,
) -> dict[str, object]:
    if re.fullmatch(r"[1-9][0-9]*", run_id) is None:
        raise ValueError("invalid source run id")
    if REPOSITORY_PATTERN.fullmatch(repository) is None:
        raise ValueError("invalid repository")
    if (
        not isinstance(run_attempt, int)
        or isinstance(run_attempt, bool)
        or run_attempt < 1
    ):
        raise ValueError("invalid source run attempt")
    result = subprocess.run(
        [
            "gh",
            "run",
            "view",
            run_id,
            "--attempt",
            str(run_attempt),
            "--repo",
            repository,
            "--json",
            "attempt,conclusion,headSha,name,startedAt,updatedAt",
        ],
        check=False,
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    if result.returncode != 0:
        detail = result.stderr.strip().splitlines()
        suffix = f": {detail[-1]}" if detail else ""
        raise RuntimeError(f"could not read source workflow timing{suffix}")
    raw = require_mapping(json.loads(result.stdout), "GitHub workflow timing response")
    raw["jobs"] = github_jobs(repository, run_id, run_attempt, timeout=timeout)
    identities = (
        load_workflow_identities(
            telemetry_root,
            repository=repository,
            run_id=run_id,
            run_attempt=run_attempt,
            commit_sha=require_string(raw.get("headSha"), "workflow commit"),
        )
        if telemetry_root is not None
        else []
    )
    return normalize(
        raw,
        repository=repository,
        run_id=run_id,
        run_attempt=run_attempt,
        identities=identities,
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repository", required=True)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--run-attempt", required=True, type=int)
    parser.add_argument("--telemetry-root", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    arguments = parser.parse_args()
    atomic_write_json(
        arguments.output,
        capture(
            arguments.repository,
            arguments.run_id,
            arguments.run_attempt,
            telemetry_root=arguments.telemetry_root,
        ),
    )


if __name__ == "__main__":
    try:
        main()
    except (
        RecursionError,
        UnicodeError,
        json.JSONDecodeError,
        OSError,
        RuntimeError,
        subprocess.TimeoutExpired,
        ValueError,
    ) as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
