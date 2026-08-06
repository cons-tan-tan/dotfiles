#!/usr/bin/env python3

"""Assemble one lane document and its available build-job shards."""

from __future__ import annotations

import argparse
import shutil
import sys
from pathlib import Path

from ci_telemetry import atomic_write_json, document, read_document, run_context


def assemble(
    lane: dict[str, object],
    jobs: list[dict[str, object]],
) -> dict[str, object]:
    lane_data = lane["data"]
    assert isinstance(lane_data, dict)
    decision = lane_data["decision"]
    assert isinstance(decision, dict)
    expected_jobs = decision["jobs"]
    assert isinstance(expected_jobs, list)
    expected = {
        item["job_id"]: item
        for item in expected_jobs
        if isinstance(item, dict) and isinstance(item.get("job_id"), str)
    }

    by_id: dict[str, dict[str, object]] = {}
    for job in jobs:
        job_run = job["run"]
        if job_run != lane["run"]:
            raise ValueError("job telemetry belongs to another CI run")
        job_data = job["data"]
        assert isinstance(job_data, dict)
        job_id = job_data.get("job_id")
        if not isinstance(job_id, str) or job_id not in expected:
            raise ValueError("job telemetry is not part of the lane decision")
        if job_id in by_id:
            raise ValueError("duplicate job telemetry shard")
        decision_job = expected[job_id]
        for field in ("telemetry_key", "system", "runner_labels", "root_drv_ids"):
            if job_data.get(field) != decision_job.get(field):
                raise ValueError(f"job telemetry has a mismatched {field}")
        by_id[job_id] = job

    missing = sorted(expected.keys() - by_id.keys())
    lane_status = lane_data.get("collection_status")
    status = "complete" if lane_status == "complete" and not missing else "partial"
    if lane_status == "failed":
        status = "failed"
    system = str(lane["run"]["system"])
    return document(
        "bundle",
        system,
        {
            "collection_status": status,
            "lane": lane,
            "jobs": [by_id[job_id] for job_id in sorted(by_id)],
            "missing_job_ids": missing,
            "missing_fragments": [],
        },
        run=lane["run"],
    )


def failed_bundle(
    system: str,
    *,
    run: dict[str, object] | None = None,
) -> dict[str, object]:
    return document(
        "bundle",
        system,
        {
            "collection_status": "failed",
            "lane": None,
            "jobs": [],
            "missing_job_ids": [],
            "missing_fragments": ["lane"],
        },
        run=run_context(system) if run is None else run,
    )


def write_result(output: Path, schema: Path, value: dict[str, object]) -> None:
    atomic_write_json(output, value)
    shutil.copyfile(schema, output.parent / schema.name)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--schema", required=True, type=Path)
    parser.add_argument("--system", required=True)
    arguments = parser.parse_args()

    lane_paths = sorted(arguments.input.glob("lane-*.json"))
    if not lane_paths:
        write_result(
            arguments.output, arguments.schema, failed_bundle(arguments.system)
        )
        return
    if len(lane_paths) != 1:
        raise ValueError("telemetry input contains multiple lane documents")
    try:
        lane = read_document(lane_paths[0], "lane")
    except (OSError, ValueError) as error:
        print(f"warning: invalid lane telemetry: {error}", file=sys.stderr)
        write_result(
            arguments.output, arguments.schema, failed_bundle(arguments.system)
        )
        return
    jobs = []
    for path in sorted(arguments.input.glob("job-*.json")):
        try:
            jobs.append(read_document(path, "job"))
        except (OSError, ValueError) as error:
            print(
                f"warning: ignoring invalid job telemetry {path.name}: {error}",
                file=sys.stderr,
            )
    write_result(arguments.output, arguments.schema, assemble(lane, jobs))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
