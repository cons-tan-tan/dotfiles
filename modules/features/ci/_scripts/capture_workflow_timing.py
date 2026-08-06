#!/usr/bin/env python3

"""Capture authoritative GitHub job timing for one completed source run."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

from ci_telemetry import atomic_write_json

COMMIT_PATTERN = re.compile(r"^[0-9a-f]{40}$")


def require_string(value: object, label: str) -> str:
    if not isinstance(value, str) or not value:
        raise ValueError(f"invalid {label}")
    return value


def normalize(
    raw: object, *, repository: str, run_id: str, run_attempt: int
) -> dict[str, object]:
    if not isinstance(raw, dict):
        raise ValueError("invalid GitHub workflow timing response")
    jobs = raw.get("jobs")
    if raw.get("name") != "CI" or not isinstance(jobs, list):
        raise ValueError("unexpected GitHub workflow timing response")
    normalized = []
    seen: set[str] = set()
    for item in jobs:
        if not isinstance(item, dict):
            raise ValueError("invalid GitHub workflow job")
        name = require_string(item.get("name"), "workflow job name")
        if name in seen:
            raise ValueError("duplicate GitHub workflow job name")
        seen.add(name)
        normalized.append(
            {
                "name": name,
                "started_at": require_string(item.get("startedAt"), "job start"),
                "completed_at": require_string(
                    item.get("completedAt"), "job completion"
                ),
                "conclusion": require_string(item.get("conclusion"), "job conclusion"),
            }
        )
    head_sha = require_string(raw.get("headSha"), "workflow commit")
    if COMMIT_PATTERN.fullmatch(head_sha) is None:
        raise ValueError("invalid workflow commit")
    if raw.get("attempt") != run_attempt:
        raise ValueError("workflow timing belongs to another attempt")
    if raw.get("conclusion") != "success":
        raise ValueError("source workflow was not successful")
    return {
        "schema_version": 1,
        "document_type": "workflow_timing",
        "repository": repository,
        "run_id": run_id,
        "run_attempt": run_attempt,
        "commit_sha": head_sha,
        "started_at": require_string(raw.get("startedAt"), "workflow start"),
        "completed_at": require_string(raw.get("updatedAt"), "workflow completion"),
        "jobs": sorted(normalized, key=lambda job: str(job["name"])),
    }


def capture(
    repository: str, run_id: str, run_attempt: int, *, timeout: float = 60
) -> dict[str, object]:
    if re.fullmatch(r"[1-9][0-9]*", run_id) is None:
        raise ValueError("invalid source run id")
    if re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository) is None:
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
            "attempt,conclusion,headSha,jobs,name,startedAt,updatedAt",
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
    return normalize(
        json.loads(result.stdout),
        repository=repository,
        run_id=run_id,
        run_attempt=run_attempt,
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repository", required=True)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--run-attempt", required=True, type=int)
    parser.add_argument("--output", required=True, type=Path)
    arguments = parser.parse_args()
    atomic_write_json(
        arguments.output,
        capture(arguments.repository, arguments.run_id, arguments.run_attempt),
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
