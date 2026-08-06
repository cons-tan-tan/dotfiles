#!/usr/bin/env python3

"""Collect telemetry fragments after their source workflow has completed."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

from assemble_ci_telemetry import assemble
from ci_telemetry import (
    PRODUCER_NAME,
    PRODUCER_VERSION,
    atomic_write_json,
    observed_at,
    read_document,
)

INDEX_SCHEMA_ID = "https://raw.githubusercontent.com/cons-tan-tan/dotfiles/main/modules/features/ci/_schemas/telemetry-run-index-v1.schema.json"
MAX_FRAGMENT_COUNT = 600
MAX_FRAGMENT_SIZE = 5 * 1024 * 1024
MAX_FRAGMENT_TOTAL_SIZE = 100 * 1024 * 1024
WORKFLOW_NAME = "CI"
WORKFLOW_PATH = ".github/workflows/ci.yaml"
ALLOWED_SOURCE_EVENTS = frozenset({"push", "workflow_dispatch"})
REASON_CODES = frozenset(
    {
        "artifact_download_failed",
        "artifact_inventory_invalid",
        "bundle_incomplete",
        "duplicate_lane",
        "fragment_invalid",
        "lane_missing",
    }
)
ALLOWED_CONCLUSIONS = frozenset(
    {
        "action_required",
        "cancelled",
        "failure",
        "neutral",
        "skipped",
        "stale",
        "startup_failure",
        "success",
        "timed_out",
    }
)


@dataclass(frozen=True)
class Fragment:
    artifact_name: str
    path: Path
    system: str
    kind: str
    telemetry_key: str | None = None


def require_mapping(value: object, label: str) -> dict[str, object]:
    if not isinstance(value, dict):
        raise ValueError(f"invalid {label}")
    return value


def require_string(value: object, label: str) -> str:
    if not isinstance(value, str) or not value:
        raise ValueError(f"invalid {label}")
    return value


def require_positive_integer(value: object, label: str) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value < 1:
        raise ValueError(f"invalid {label}")
    return value


def nullable_timestamp(value: object, label: str) -> str | None:
    if value is not None and (not isinstance(value, str) or not value):
        raise ValueError(f"invalid {label}")
    if isinstance(value, str):
        try:
            parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError as error:
            raise ValueError(f"invalid {label}") from error
        if parsed.tzinfo is None:
            raise ValueError(f"invalid {label}")
    return value


def normalize_workflow_path(raw_path: str, default_branch: str) -> str:
    workflow_path, separator, workflow_ref = raw_path.rpartition("@")
    if not separator:
        workflow_path = raw_path
    elif workflow_ref not in {default_branch, f"refs/heads/{default_branch}"}:
        raise ValueError("source workflow path has an unexpected ref")
    if workflow_path != WORKFLOW_PATH:
        raise ValueError("unexpected source workflow")
    return workflow_path


def source_from_event(path: Path) -> dict[str, object]:
    event = require_mapping(json.loads(path.read_text()), "workflow_run event")
    if event.get("action") != "completed":
        raise ValueError("workflow_run event is not completed")
    repository = require_mapping(event.get("repository"), "event repository")
    workflow_run = require_mapping(event.get("workflow_run"), "source workflow run")
    repository_name = require_string(repository.get("full_name"), "repository name")
    repository_id = str(require_positive_integer(repository.get("id"), "repository id"))
    default_branch = require_string(
        repository.get("default_branch"), "repository default branch"
    )
    source_repository = workflow_run.get("repository")
    if source_repository is not None:
        source_repository = require_mapping(source_repository, "source repository")
        if str(source_repository.get("id")) != repository_id:
            raise ValueError("source workflow belongs to another repository")

    name = require_string(workflow_run.get("name"), "source workflow name")
    workflow_path = normalize_workflow_path(
        require_string(workflow_run.get("path"), "source workflow path"),
        default_branch,
    )
    source_event = require_string(workflow_run.get("event"), "source event")
    head_branch = require_string(workflow_run.get("head_branch"), "source head branch")
    head_sha = require_string(workflow_run.get("head_sha"), "source head sha")
    conclusion = require_string(workflow_run.get("conclusion"), "source conclusion")
    if name != WORKFLOW_NAME:
        raise ValueError("unexpected source workflow")
    if source_event not in ALLOWED_SOURCE_EVENTS:
        raise ValueError("untrusted source event")
    if head_branch != default_branch:
        raise ValueError("source workflow did not run on the default branch")
    if re.fullmatch(r"[0-9a-f]{40}", head_sha) is None:
        raise ValueError("invalid source head sha")
    if conclusion not in ALLOWED_CONCLUSIONS:
        raise ValueError("invalid source conclusion")
    if workflow_run.get("status") != "completed":
        raise ValueError("source workflow is not completed")

    return {
        "repository": repository_name,
        "repository_id": repository_id,
        "workflow_id": str(
            require_positive_integer(workflow_run.get("workflow_id"), "workflow id")
        ),
        "workflow_name": name,
        "workflow_path": workflow_path,
        "run_id": str(
            require_positive_integer(workflow_run.get("id"), "source run id")
        ),
        "run_attempt": require_positive_integer(
            workflow_run.get("run_attempt"), "source run attempt"
        ),
        "event": source_event,
        "head_sha": head_sha,
        "head_branch": head_branch,
        "conclusion": conclusion,
        "created_at": nullable_timestamp(workflow_run.get("created_at"), "created_at"),
        "run_started_at": nullable_timestamp(
            workflow_run.get("run_started_at"), "run_started_at"
        ),
        "updated_at": nullable_timestamp(workflow_run.get("updated_at"), "updated_at"),
        "trust_tier": "trusted_default_branch",
    }


def collector_context() -> dict[str, object]:
    run_attempt = os.environ.get("GITHUB_RUN_ATTEMPT", "")
    commit_sha = os.environ.get("GITHUB_SHA", "")
    if not run_attempt.isdigit() or int(run_attempt) < 1:
        raise ValueError("invalid collector run attempt")
    if re.fullmatch(r"[0-9a-f]{40}", commit_sha) is None:
        raise ValueError("invalid collector commit sha")
    return {
        "run_id": require_string(os.environ.get("GITHUB_RUN_ID"), "collector run id"),
        "run_attempt": int(run_attempt),
        "commit_sha": commit_sha,
    }


def expected_run(source: dict[str, object], system: str) -> dict[str, object]:
    return {
        "repository": source["repository"],
        "repository_id": source["repository_id"],
        "run_id": source["run_id"],
        "run_attempt": source["run_attempt"],
        "workflow": source["workflow_name"],
        "event": source["event"],
        "ref": f"refs/heads/{source['head_branch']}",
        "commit_sha": source["head_sha"],
        "system": system,
    }


def fragment_for_directory(
    directory: Path, prefix: str, systems: list[str]
) -> Fragment:
    name = directory.name
    suffix = name.removeprefix(prefix)
    if suffix == name:
        raise ValueError("artifact has an unexpected source identity")
    for system in sorted(systems, key=len, reverse=True):
        if suffix == f"{system}-lane":
            return Fragment(name, directory / f"lane-{system}.json", system, "lane")
        job_match = re.fullmatch(rf"{re.escape(system)}-([0-9a-f]{{20}})", suffix)
        if job_match is not None:
            key = job_match.group(1)
            return Fragment(name, directory / f"job-{key}.json", system, "job", key)
    raise ValueError("artifact has an unexpected system or fragment identity")


def discover_fragments(
    root: Path, source: dict[str, object], systems: list[str]
) -> dict[str, list[Fragment]]:
    result = {system: [] for system in systems}
    if not root.exists():
        return result
    if root.is_symlink() or not root.is_dir():
        raise ValueError("fragment input is not a directory")
    prefix = f"ci-telemetry-fragment-{source['run_id']}-{source['run_attempt']}-"
    total_size = 0
    directories = sorted(root.iterdir())
    if len(directories) > MAX_FRAGMENT_COUNT:
        raise ValueError("artifact fragments exceed collection limits")
    for directory in directories:
        if directory.is_symlink() or not directory.is_dir():
            raise ValueError("fragment input contains an unexpected entry")
        fragment = fragment_for_directory(directory, prefix, systems)
        entries = list(directory.iterdir())
        if len(entries) != 1 or entries[0] != fragment.path:
            raise ValueError("artifact has an unexpected file inventory")
        if fragment.path.is_symlink() or not fragment.path.is_file():
            raise ValueError("artifact fragment is not a regular file")
        size = fragment.path.stat().st_size
        if size > MAX_FRAGMENT_SIZE:
            raise ValueError("artifact fragment exceeds the size limit")
        total_size += size
        if total_size > MAX_FRAGMENT_TOTAL_SIZE:
            raise ValueError("artifact fragments exceed collection limits")
        result[fragment.system].append(fragment)
    return result


def unavailable_system(system: str, status: str, reason: str) -> dict[str, object]:
    return {
        "system": system,
        "artifact_status": status,
        "reason_code": reason,
        "bundle_path": None,
        "bundle_sha256": None,
        "bundle_collection_status": None,
        "execution_conclusion": "unknown",
    }


def collect_system(
    system: str,
    fragments: list[Fragment],
    source: dict[str, object],
    output: Path,
) -> dict[str, object]:
    lane_fragments = [fragment for fragment in fragments if fragment.kind == "lane"]
    job_fragments = [fragment for fragment in fragments if fragment.kind == "job"]
    if not lane_fragments:
        return unavailable_system(system, "missing", "lane_missing")
    if len(lane_fragments) != 1:
        return unavailable_system(system, "invalid", "duplicate_lane")
    try:
        lane = read_document(lane_fragments[0].path, "lane")
        if lane.get("run") != expected_run(source, system):
            raise ValueError("lane source identity mismatch")
        jobs = []
        seen_keys: set[str] = set()
        for fragment in sorted(job_fragments, key=lambda item: item.artifact_name):
            if fragment.telemetry_key in seen_keys:
                raise ValueError("duplicate job telemetry key")
            assert fragment.telemetry_key is not None
            seen_keys.add(fragment.telemetry_key)
            job = read_document(fragment.path, "job")
            if job.get("run") != expected_run(source, system):
                raise ValueError("job source identity mismatch")
            data = require_mapping(job.get("data"), "job data")
            if data.get("telemetry_key") != fragment.telemetry_key:
                raise ValueError("job artifact identity mismatch")
            jobs.append(job)
        bundle = assemble(lane, jobs)
    except (OSError, RecursionError, UnicodeError, ValueError):
        return unavailable_system(system, "invalid", "fragment_invalid")

    relative_path = Path("systems") / f"{system}.json"
    bundle_path = output / relative_path
    atomic_write_json(bundle_path, bundle)
    digest = hashlib.sha256(bundle_path.read_bytes()).hexdigest()
    bundle_data = require_mapping(bundle.get("data"), "bundle data")
    bundle_status = require_string(
        bundle_data.get("collection_status"), "bundle collection status"
    )
    return {
        "system": system,
        "artifact_status": "available",
        "reason_code": None if bundle_status == "complete" else "bundle_incomplete",
        "bundle_path": relative_path.as_posix(),
        "bundle_sha256": digest,
        "bundle_collection_status": bundle_status,
        "execution_conclusion": "unknown",
    }


def collection_status(systems: list[dict[str, object]]) -> str:
    available = [item for item in systems if item["artifact_status"] == "available"]
    if len(available) == len(systems) and all(
        item["bundle_collection_status"] == "complete" for item in available
    ):
        return "complete"
    return "partial" if available else "failed"


def validate_run_index(index: dict[str, object]) -> None:
    expected_systems = index.get("expected_systems")
    system_entries = index.get("systems")
    if (
        not isinstance(expected_systems, list)
        or not expected_systems
        or expected_systems != sorted(set(expected_systems))
        or not all(isinstance(system, str) and system for system in expected_systems)
    ):
        raise ValueError("invalid expected systems")
    if (
        not isinstance(system_entries, list)
        or [
            entry.get("system") if isinstance(entry, dict) else None
            for entry in system_entries
        ]
        != expected_systems
    ):
        raise ValueError("run index systems do not match the expected systems")
    for entry in system_entries:
        assert isinstance(entry, dict)
        status = entry.get("artifact_status")
        reason = entry.get("reason_code")
        bundle_values = (
            entry.get("bundle_path"),
            entry.get("bundle_sha256"),
            entry.get("bundle_collection_status"),
        )
        if reason is not None and reason not in REASON_CODES:
            raise ValueError("invalid system reason code")
        if status == "available":
            path, digest, bundle_status = bundle_values
            if (
                not isinstance(path, str)
                or not path.startswith("systems/")
                or re.fullmatch(r"[0-9a-f]{64}", str(digest)) is None
                or bundle_status not in {"complete", "partial", "failed"}
                or (bundle_status == "complete" and reason is not None)
                or (bundle_status != "complete" and reason != "bundle_incomplete")
            ):
                raise ValueError("invalid available system entry")
        elif status in {"missing", "invalid"}:
            if any(value is not None for value in bundle_values) or not isinstance(
                reason, str
            ):
                raise ValueError("invalid unavailable system entry")
            if status == "missing" and reason != "lane_missing":
                raise ValueError("invalid missing system reason")
            if status == "invalid" and reason not in {
                "artifact_download_failed",
                "artifact_inventory_invalid",
                "duplicate_lane",
                "fragment_invalid",
            }:
                raise ValueError("invalid invalid-system reason")
        else:
            raise ValueError("invalid system artifact status")
    if index.get("collection_status") != collection_status(system_entries):
        raise ValueError("invalid run index collection status")
    if index.get("artifact_download_status") not in {"success", "failed"}:
        raise ValueError("invalid artifact download status")


def collect(
    *,
    event: Path,
    fragment_root: Path,
    output: Path,
    schema: Path,
    index_schema: Path,
    systems: list[str],
    download_outcome: str = "success",
) -> dict[str, object]:
    expected_systems = sorted(set(systems))
    if not expected_systems or len(expected_systems) != len(systems):
        raise ValueError("expected systems must be non-empty and unique")
    source = source_from_event(event)
    collector = collector_context()
    output.mkdir(parents=True, exist_ok=True)
    (output / "schemas").mkdir(exist_ok=True)
    shutil.copyfile(schema, output / "schemas" / schema.name)
    shutil.copyfile(index_schema, output / "schemas" / index_schema.name)
    if download_outcome != "success":
        system_entries = [
            unavailable_system(system, "invalid", "artifact_download_failed")
            for system in expected_systems
        ]
    else:
        try:
            fragments = discover_fragments(fragment_root, source, expected_systems)
        except (OSError, ValueError):
            system_entries = [
                unavailable_system(system, "invalid", "artifact_inventory_invalid")
                for system in expected_systems
            ]
        else:
            system_entries = [
                collect_system(system, fragments[system], source, output)
                for system in expected_systems
            ]
    index = {
        "$schema": INDEX_SCHEMA_ID,
        "schema_version": 1,
        "document_type": "run_index",
        "producer": {"name": PRODUCER_NAME, "version": PRODUCER_VERSION},
        "observed_at": observed_at(),
        "source": source,
        "collector": collector,
        "artifact_download_status": download_outcome,
        "collection_status": collection_status(system_entries),
        "expected_systems": expected_systems,
        "systems": system_entries,
    }
    validate_run_index(index)
    atomic_write_json(output / "index.json", index)
    return index


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--event", required=True, type=Path)
    parser.add_argument(
        "--download-outcome", required=True, choices=("success", "failure")
    )
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--schema", required=True, type=Path)
    parser.add_argument("--index-schema", required=True, type=Path)
    parser.add_argument("--system", required=True, action="append")
    arguments = parser.parse_args()
    collect(
        event=arguments.event,
        fragment_root=arguments.input,
        output=arguments.output,
        schema=arguments.schema,
        index_schema=arguments.index_schema,
        systems=arguments.system,
        download_outcome=(
            "success" if arguments.download_outcome == "success" else "failed"
        ),
    )


if __name__ == "__main__":
    try:
        main()
    except (
        json.JSONDecodeError,
        OSError,
        RecursionError,
        UnicodeError,
        ValueError,
    ) as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
