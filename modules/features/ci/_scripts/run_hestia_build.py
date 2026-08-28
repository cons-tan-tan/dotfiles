#!/usr/bin/env python3

"""Run a Hestia matrix build and emit a versioned telemetry shard."""

from __future__ import annotations

import json
import os
import shlex
import subprocess
import sys
import time
from pathlib import Path

from ci_telemetry import atomic_write_json, document, drv_id

ACT_BUILD = 105
ACT_SUBSTITUTE = 108
EVENT_PARSER_VERSION = "1"


def phase(status: str, duration_ms: int, exit_code: int | None) -> dict[str, object]:
    return {"status": status, "duration_ms": duration_ms, "exit_code": exit_code}


def run_prefetch(hestia_bin: str, installables: list[str]) -> tuple[int, int]:
    started = time.monotonic()
    result = subprocess.run(
        [hestia_bin, "prefetch", *installables],
        check=False,
    )
    duration = round((time.monotonic() - started) * 1000)
    return result.returncode, duration


def printable_message(event: dict[str, object], raw: str) -> str:
    message = event.get("msg") or event.get("text")
    if isinstance(message, str) and message:
        return message
    return "" if event.get("action") in {"start", "stop"} else raw


def store_id(path: str) -> str:
    name = path.removeprefix("/nix/store/")
    return name.split("-", 1)[0] if "-" in name else name


def run_build(
    installables: list[str],
) -> tuple[int, int, list[dict[str, object]], list[dict[str, object]]]:
    command = [
        "nix",
        "build",
        "--no-link",
        "--log-format",
        "internal-json",
        *installables,
    ]
    started = time.monotonic()
    process = subprocess.Popen(command, stderr=subprocess.PIPE, text=True, bufsize=1)
    assert process.stderr is not None
    activities: dict[object, tuple[str, str, float]] = {}
    completed: list[dict[str, object]] = []
    substitutions: list[dict[str, object]] = []
    for raw_line in process.stderr:
        line = raw_line.rstrip("\n")
        if not line.startswith("@nix "):
            print(line, file=sys.stderr)
            continue
        try:
            event = json.loads(line[5:])
        except json.JSONDecodeError:
            print(line, file=sys.stderr)
            continue
        action = event.get("action")
        activity_id = event.get("id")
        activity_type = event.get("type")
        if action == "start" and activity_type in {ACT_BUILD, ACT_SUBSTITUTE}:
            fields = event.get("fields")
            if isinstance(fields, list) and fields and isinstance(fields[0], str):
                kind = "build" if activity_type == ACT_BUILD else "substitute"
                activities[activity_id] = (kind, fields[0], time.monotonic())
        elif action == "stop" and activity_id in activities:
            kind, store_path, activity_started = activities.pop(activity_id)
            event_data = {
                "outcome": "completed",
                "duration_ms": round((time.monotonic() - activity_started) * 1000),
            }
            if kind == "build":
                event_data.update(
                    {"drv_id": drv_id(store_path), "drv_path": store_path}
                )
                completed.append(event_data)
            else:
                event_data.update(
                    {"store_id": store_id(store_path), "store_path": store_path}
                )
                substitutions.append(event_data)
        message = printable_message(event, line)
        if message:
            print(message, file=sys.stderr)
    process.stderr.close()
    return_code = process.wait()
    for kind, store_path, activity_started in activities.values():
        event_data = {
            "outcome": "interrupted",
            "duration_ms": round((time.monotonic() - activity_started) * 1000),
        }
        if kind == "build":
            event_data.update({"drv_id": drv_id(store_path), "drv_path": store_path})
            completed.append(event_data)
        else:
            event_data.update(
                {"store_id": store_id(store_path), "store_path": store_path}
            )
            substitutions.append(event_data)
    return (
        return_code,
        round((time.monotonic() - started) * 1000),
        sorted(
            completed, key=lambda item: (str(item["drv_id"]), int(item["duration_ms"]))
        ),
        sorted(
            substitutions,
            key=lambda item: (str(item["store_id"]), int(item["duration_ms"])),
        ),
    )


def run_matrix_build(
    hestia_bin: str, installables: list[str]
) -> tuple[
    int,
    dict[str, dict[str, object]],
    list[dict[str, object]],
    list[dict[str, object]],
]:
    # A completed prefetch failure is recoverable through normal substitution.
    # Spawn failures remain infrastructure errors and are handled by the CLI entry point.
    prefetch_code, prefetch_ms = run_prefetch(hestia_bin, installables)
    if prefetch_code != 0:
        print(
            "::warning::Hestia closure prefetch failed; "
            "falling back to normal Nix substitution",
            file=sys.stderr,
        )
    build_code, build_ms, events, substitutions = run_build(installables)
    return (
        build_code,
        {
            "prefetch": phase(
                "success" if prefetch_code == 0 else "fallback",
                prefetch_ms,
                prefetch_code,
            ),
            "nix_build": phase(
                "success" if build_code == 0 else "failure", build_ms, build_code
            ),
        },
        events,
        substitutions,
    )


def required(name: str) -> str:
    value = os.environ.get(name)
    if value is None or not value:
        raise ValueError(f"missing environment variable: {name}")
    return value


def nix_version() -> str:
    result = subprocess.run(
        ["nix", "--version"], check=False, capture_output=True, text=True, timeout=5
    )
    return result.stdout.strip() if result.returncode == 0 else "unknown"


def job_started_at_ms() -> int:
    raw = Path(required("CI_JOB_STARTED_AT")).read_text().strip()
    if not raw.isdigit():
        raise ValueError("invalid CI job start marker")
    return int(raw) * 1000


def main() -> int:
    job_started = job_started_at_ms()
    wrapper_started = round(time.time() * 1000)
    installables = shlex.split(required("INSTALLABLES"))
    root_ids = sorted(drv_id(value.removesuffix("^*")) for value in installables)
    build_code, build_phases, events, substitutions = run_matrix_build(
        required("HESTIA_BIN"), installables
    )

    system = required("SYSTEM")
    job = document(
        "job",
        system,
        {
            "workflow_job": {
                "role": "system-build",
                "runner_name": required("TELEMETRY_RUNNER_NAME"),
            },
            "job_id": required("TELEMETRY_JOB_ID"),
            "telemetry_key": required("TELEMETRY_KEY"),
            "name": required("TELEMETRY_JOB_NAME"),
            "system": system,
            "runner_labels": sorted(
                label
                for label in required("TELEMETRY_RUNNER_LABELS").split(",")
                if label
            ),
            "root_drv_ids": root_ids,
            "status": "success" if build_code == 0 else "failure",
            "phases": {
                "github_job_setup": phase(
                    "success", max(0, wrapper_started - job_started), 0
                ),
                **build_phases,
            },
            "derivation_events": events,
            "substitution_events": substitutions,
            "measurement_quality": (
                "structured_nix_events" if events else "job_wall_clock"
            ),
            "nix_version": nix_version(),
            "event_parser_version": EVENT_PARSER_VERSION,
            "event_parse_status": (
                "events_observed" if events or substitutions else "no_events"
            ),
            "total_duration_ms": max(0, round(time.time() * 1000) - job_started),
        },
    )
    atomic_write_json(required("CI_TELEMETRY_JOB"), job)
    return build_code


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
