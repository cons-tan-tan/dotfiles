#!/usr/bin/env python3

"""Stable CI telemetry primitives shared by producers and aggregators."""

from __future__ import annotations

import hashlib
import json
import os
import re
import tempfile
from collections.abc import Iterable
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

SCHEMA_ID = "https://raw.githubusercontent.com/cons-tan-tan/dotfiles/main/modules/features/ci/_schemas/telemetry-v1.schema.json"
SCHEMA_VERSION = 1
PRODUCER_NAME = "dotfiles-ci-telemetry"
PRODUCER_VERSION = "1.0.0"
DOCUMENT_TYPES = frozenset({"lane", "job", "bundle", "workflow_job"})


def canonical_json(value: object) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True)


def stable_hash(parts: Iterable[str]) -> str:
    payload = "\0".join(parts).encode()
    return hashlib.sha256(payload).hexdigest()


def drv_id(drv_path: str) -> str:
    match = re.fullmatch(r"/nix/store/([0-9a-z]{32})-[^/]+\.drv", drv_path)
    if not match:
        raise ValueError(f"invalid derivation path: {drv_path}")
    return match.group(1)


def check_id(system: str, attr_path: str) -> str:
    return f"{system}:{attr_path}"


def job_identity(
    *, system: str, runner_labels: Iterable[str], member_check_ids: Iterable[str]
) -> tuple[str, str]:
    digest = stable_hash(
        [
            "hestia-overlap-v1",
            system,
            *sorted(runner_labels),
            *sorted(member_check_ids),
        ]
    )
    return digest, digest[:20]


def observed_at() -> str:
    return (
        datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
    )


def run_context(system: str) -> dict[str, object]:
    attempt = os.environ.get("GITHUB_RUN_ATTEMPT", "1")
    if not attempt.isdigit() or int(attempt) < 1:
        attempt = "1"
    return {
        "repository": os.environ.get("GITHUB_REPOSITORY", "local/unknown"),
        "repository_id": os.environ.get("GITHUB_REPOSITORY_ID", "unknown"),
        "run_id": os.environ.get("GITHUB_RUN_ID", "local"),
        "run_attempt": int(attempt),
        "workflow": os.environ.get("GITHUB_WORKFLOW", "local"),
        "event": os.environ.get("GITHUB_EVENT_NAME", "local"),
        "ref": os.environ.get("GITHUB_REF", "local"),
        "commit_sha": os.environ.get("GITHUB_SHA", "0" * 40),
        "system": system,
    }


def document(
    document_type: str,
    system: str,
    data: dict[str, object],
    *,
    run: dict[str, object] | None = None,
) -> dict[str, object]:
    result = {
        "$schema": SCHEMA_ID,
        "schema_version": SCHEMA_VERSION,
        "document_type": document_type,
        "producer": {
            "name": PRODUCER_NAME,
            "version": PRODUCER_VERSION,
        },
        "run": run_context(system) if run is None else run,
        "observed_at": observed_at(),
        "data": data,
    }
    validate_document(result)
    return result


def validate_document(value: object, expected_type: str | None = None) -> None:
    if not isinstance(value, dict):
        raise ValueError("telemetry document must be an object")
    if (
        value.get("$schema") != SCHEMA_ID
        or value.get("schema_version") != SCHEMA_VERSION
    ):
        raise ValueError("unsupported telemetry schema")
    document_type = value.get("document_type")
    if document_type not in DOCUMENT_TYPES:
        raise ValueError("invalid telemetry document type")
    if expected_type is not None and document_type != expected_type:
        raise ValueError(f"expected {expected_type} telemetry")
    require_keys(
        value,
        {
            "$schema",
            "schema_version",
            "document_type",
            "producer",
            "run",
            "observed_at",
            "data",
        },
        "telemetry envelope",
    )
    producer = value.get("producer")
    run = value.get("run")
    if not isinstance(producer, dict):
        raise ValueError("invalid telemetry producer")
    require_keys(producer, {"name", "version"}, "telemetry producer")
    if producer.get("name") != PRODUCER_NAME or not nonempty(producer.get("version")):
        raise ValueError("invalid telemetry producer")
    if not isinstance(run, dict):
        raise ValueError("invalid telemetry run context")
    require_keys(
        run,
        {
            "repository",
            "repository_id",
            "run_id",
            "run_attempt",
            "workflow",
            "event",
            "ref",
            "commit_sha",
            "system",
        },
        "telemetry run context",
    )
    if not all(
        nonempty(run.get(key))
        for key in (
            "repository",
            "repository_id",
            "run_id",
            "workflow",
            "event",
            "ref",
            "system",
        )
    ):
        raise ValueError("invalid telemetry run context")
    if not integer(run.get("run_attempt"), minimum=1):
        raise ValueError("invalid telemetry run attempt")
    if not re.fullmatch(r"[0-9a-f]{40}", str(run.get("commit_sha", ""))):
        raise ValueError("invalid telemetry commit")
    if not isinstance(value.get("observed_at"), str) or not isinstance(
        value.get("data"), dict
    ):
        raise ValueError("invalid telemetry envelope")
    data = value["data"]
    assert isinstance(data, dict)
    if document_type == "lane":
        validate_lane(data, str(run["system"]))
    elif document_type == "job":
        validate_job(data, str(run["system"]))
    elif document_type == "bundle":
        validate_bundle(data, run)
    else:
        validate_workflow_job(data)


def nonempty(value: object) -> bool:
    return isinstance(value, str) and bool(value)


def integer(value: object, *, minimum: int = 0) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and value >= minimum


def number_between(value: object, minimum: float, maximum: float) -> bool:
    return (
        isinstance(value, (int, float))
        and not isinstance(value, bool)
        and minimum <= value <= maximum
    )


def valid_drv_id(value: object) -> bool:
    return isinstance(value, str) and re.fullmatch(r"[0-9a-z]{32}", value) is not None


def require_keys(value: dict[str, Any], keys: set[str], label: str) -> None:
    if set(value) != keys:
        raise ValueError(f"invalid {label} fields")


def require_optional_keys(
    value: dict[str, Any], required: set[str], optional: set[str], label: str
) -> None:
    if not required.issubset(value) or not set(value).issubset(required | optional):
        raise ValueError(f"invalid {label} fields")


def validate_workflow_job_identity(value: object, expected_role: str) -> None:
    if not isinstance(value, dict):
        raise ValueError("invalid workflow job identity")
    require_keys(value, {"role", "runner_name"}, "workflow job identity")
    if value.get("role") != expected_role or not nonempty(value.get("runner_name")):
        raise ValueError("invalid workflow job identity")


def validate_workflow_job(data: dict[str, Any]) -> None:
    validate_workflow_job_identity(data, "flake-eval")


def string_list(value: object, label: str) -> list[str]:
    if not isinstance(value, list) or not all(nonempty(item) for item in value):
        raise ValueError(f"invalid {label}")
    if value != sorted(set(value)):
        raise ValueError(f"{label} must be unique and sorted")
    return value


def validate_plan(value: object) -> set[str]:
    if not isinstance(value, dict):
        raise ValueError("invalid telemetry plan")
    require_keys(value, {"status", "dependency_drv_ids"}, "telemetry plan")
    if value["status"] not in {"success", "failed", "timeout", "not_observed"}:
        raise ValueError("invalid telemetry plan status")
    return set(string_list(value["dependency_drv_ids"], "dependency drv IDs"))


def validate_lane(data: dict[str, Any], expected_system: str) -> None:
    require_optional_keys(
        data,
        {
            "collection_status",
            "source",
            "derivations",
            "checks",
            "static_groups",
            "decision",
        },
        {"workflow_job"},
        "lane telemetry",
    )
    if "workflow_job" in data:
        validate_workflow_job_identity(data["workflow_job"], "system-evaluate")
    if data["collection_status"] not in {"complete", "partial", "failed"}:
        raise ValueError("invalid lane collection status")
    source = data["source"]
    if not isinstance(source, dict):
        raise ValueError("invalid lane source")
    require_keys(
        source,
        {
            "hestia_version",
            "manifest_version",
            "nix_version",
            "plan_method",
            "plan_duration_ms",
        },
        "lane source",
    )
    if source["plan_method"] != "single-dry-run-and-store-requisites-v1":
        raise ValueError("invalid lane plan method")
    if not all(
        nonempty(source[key])
        for key in ("hestia_version", "manifest_version", "nix_version")
    ) or not integer(source["plan_duration_ms"]):
        raise ValueError("invalid lane source values")
    derivations = data["derivations"]
    checks = data["checks"]
    groups = data["static_groups"]
    if not all(isinstance(value, list) for value in (derivations, checks, groups)):
        raise ValueError("invalid lane collections")
    derivation_ids: set[str] = set()
    for item in derivations:
        if not isinstance(item, dict):
            raise ValueError("invalid derivation telemetry")
        require_keys(item, {"drv_id", "drv_path"}, "derivation telemetry")
        if (
            item["drv_id"] != drv_id(str(item["drv_path"]))
            or item["drv_id"] in derivation_ids
        ):
            raise ValueError("invalid or duplicate derivation telemetry")
        derivation_ids.add(item["drv_id"])
    check_ids: set[str] = set()
    for item in checks:
        if not isinstance(item, dict):
            raise ValueError("invalid check telemetry")
        require_keys(
            item,
            {
                "check_id",
                "attr_path",
                "display_name",
                "drv_id",
                "drv_path",
                "system",
                "runner_labels",
                "static_affinity_group",
                "selection",
                "plan",
            },
            "check telemetry",
        )
        identity = str(item["check_id"])
        if identity in check_ids or item["drv_id"] != drv_id(str(item["drv_path"])):
            raise ValueError("invalid or duplicate check telemetry")
        check_ids.add(identity)
        if item["system"] != expected_system:
            raise ValueError("check telemetry belongs to another system")
        if identity != check_id(expected_system, str(item["attr_path"])):
            raise ValueError("check telemetry has an invalid stable identity")
        if not nonempty(item["display_name"]):
            raise ValueError("check telemetry has an invalid display name")
        if item["selection"] not in {"scheduled", "cached_filtered", "unknown"}:
            raise ValueError("invalid check selection")
        if item["static_affinity_group"] is not None and not nonempty(
            item["static_affinity_group"]
        ):
            raise ValueError("invalid check affinity group")
        string_list(item["runner_labels"], "check runner labels")
        if not validate_plan(item["plan"]).issubset(derivation_ids):
            raise ValueError("check plan references an unknown derivation")
    for group in groups:
        if not isinstance(group, dict):
            raise ValueError("invalid static group telemetry")
        require_keys(
            group,
            {
                "name",
                "system",
                "runner_labels",
                "member_check_ids",
                "root_drv_ids",
                "plan",
            },
            "static group telemetry",
        )
        if group["system"] != expected_system:
            raise ValueError("static group belongs to another system")
        if not nonempty(group["name"]):
            raise ValueError("invalid static group name")
        string_list(group["runner_labels"], "group runner labels")
        if not set(string_list(group["member_check_ids"], "group members")).issubset(
            check_ids
        ):
            raise ValueError("static group references an unknown check")
        group_roots = string_list(group["root_drv_ids"], "group root drv IDs")
        if not all(valid_drv_id(value) for value in group_roots):
            raise ValueError("invalid static group root drv ID")
        if not validate_plan(group["plan"]).issubset(derivation_ids):
            raise ValueError("group plan references an unknown derivation")
    decision = data["decision"]
    if not isinstance(decision, dict):
        raise ValueError("invalid decision telemetry")
    require_keys(
        decision,
        {
            "algorithm",
            "algorithm_version",
            "status",
            "reason_code",
            "parameters",
            "input_fingerprint",
            "jobs",
        },
        "decision telemetry",
    )
    if (
        decision["algorithm"] != "hestia-overlap"
        or decision["algorithm_version"] != "1"
    ):
        raise ValueError("invalid decision algorithm")
    if decision["status"] not in {
        "optimized",
        "unchanged",
        "fallback",
        "not_needed",
    }:
        raise ValueError("invalid decision status")
    if decision["reason_code"] is not None and not nonempty(decision["reason_code"]):
        raise ValueError("invalid decision reason")
    parameters = decision["parameters"]
    if not isinstance(parameters, dict):
        raise ValueError("invalid optimizer parameters")
    require_keys(
        parameters,
        {"critical_path_slack", "min_shared_derivations", "min_shared_ratio"},
        "optimizer parameters",
    )
    if not integer(parameters["min_shared_derivations"], minimum=1) or not all(
        number_between(parameters[key], 0, 1)
        for key in ("critical_path_slack", "min_shared_ratio")
    ):
        raise ValueError("invalid optimizer parameters")
    if not re.fullmatch(r"[0-9a-f]{64}", str(decision["input_fingerprint"])):
        raise ValueError("invalid decision fingerprint")
    jobs = decision["jobs"]
    if not isinstance(jobs, list):
        raise ValueError("invalid decision jobs")
    job_ids: set[str] = set()
    telemetry_keys: set[str] = set()
    for item in jobs:
        if not isinstance(item, dict):
            raise ValueError("invalid decision job")
        require_keys(
            item,
            {
                "job_id",
                "telemetry_key",
                "name",
                "system",
                "runner_labels",
                "member_check_ids",
                "root_drv_ids",
                "planned_drv_ids",
            },
            "decision job",
        )
        if item["job_id"] in job_ids or item["telemetry_key"] in telemetry_keys:
            raise ValueError("duplicate decision job identity")
        if not re.fullmatch(r"[0-9a-f]{64}", str(item["job_id"])) or not re.fullmatch(
            r"[0-9a-f]{20}", str(item["telemetry_key"])
        ):
            raise ValueError("invalid decision job identity")
        job_ids.add(item["job_id"])
        telemetry_keys.add(item["telemetry_key"])
        if item["system"] != expected_system:
            raise ValueError("decision job belongs to another system")
        string_list(item["runner_labels"], "job runner labels")
        if not set(string_list(item["member_check_ids"], "job members")).issubset(
            check_ids
        ):
            raise ValueError("decision job references an unknown check")
        roots = string_list(item["root_drv_ids"], "job root drv IDs")
        if not all(valid_drv_id(value) for value in roots):
            raise ValueError("invalid decision root drv ID")
        if not set(
            string_list(item["planned_drv_ids"], "job planned drv IDs")
        ).issubset(derivation_ids):
            raise ValueError("decision job references an unknown derivation")


def validate_job(data: dict[str, Any], expected_system: str) -> None:
    require_optional_keys(
        data,
        {
            "job_id",
            "telemetry_key",
            "name",
            "system",
            "runner_labels",
            "root_drv_ids",
            "status",
            "phases",
            "derivation_events",
            "substitution_events",
            "measurement_quality",
            "nix_version",
            "event_parser_version",
            "event_parse_status",
            "total_duration_ms",
        },
        {"workflow_job"},
        "job telemetry",
    )
    if "workflow_job" in data:
        validate_workflow_job_identity(data["workflow_job"], "system-build")
    if not re.fullmatch(r"[0-9a-f]{64}", str(data["job_id"])) or not re.fullmatch(
        r"[0-9a-f]{20}", str(data["telemetry_key"])
    ):
        raise ValueError("invalid job identity")
    if data["system"] != expected_system:
        raise ValueError("job telemetry belongs to another system")
    string_list(data["runner_labels"], "job runner labels")
    roots = string_list(data["root_drv_ids"], "job root drv IDs")
    if not all(valid_drv_id(value) for value in roots):
        raise ValueError("invalid job root drv ID")
    phases = data["phases"]
    if not isinstance(phases, dict):
        raise ValueError("invalid job phases")
    require_keys(phases, {"github_job_setup", "prefetch", "nix_build"}, "job phases")
    for item in phases.values():
        if not isinstance(item, dict):
            raise ValueError("invalid job phase")
        require_keys(item, {"status", "duration_ms", "exit_code"}, "job phase")
        if item["status"] not in {"success", "fallback", "failure", "not_run"}:
            raise ValueError("invalid job phase status")
        if not integer(item["duration_ms"]):
            raise ValueError("invalid job phase duration")
        if item["exit_code"] is not None and (
            not isinstance(item["exit_code"], int)
            or isinstance(item["exit_code"], bool)
        ):
            raise ValueError("invalid job phase exit code")
    if not isinstance(data["derivation_events"], list) or not isinstance(
        data["substitution_events"], list
    ):
        raise ValueError("invalid job events")
    for event in data["derivation_events"]:
        if not isinstance(event, dict):
            raise ValueError("invalid derivation event")
        require_keys(
            event, {"drv_id", "drv_path", "outcome", "duration_ms"}, "derivation event"
        )
        if event["drv_id"] != drv_id(str(event["drv_path"])):
            raise ValueError("invalid derivation event identity")
        if event["outcome"] not in {"completed", "interrupted"} or not integer(
            event["duration_ms"]
        ):
            raise ValueError("invalid derivation event result")
    for event in data["substitution_events"]:
        if not isinstance(event, dict):
            raise ValueError("invalid substitution event")
        require_keys(
            event,
            {"store_id", "store_path", "outcome", "duration_ms"},
            "substitution event",
        )
        if (
            not nonempty(event["store_id"])
            or not isinstance(event["store_path"], str)
            or not event["store_path"].startswith("/nix/store/")
            or event["outcome"] not in {"completed", "interrupted"}
            or not integer(event["duration_ms"])
        ):
            raise ValueError("invalid substitution event result")
    if data["status"] not in {"success", "failure", "interrupted"}:
        raise ValueError("invalid job status")
    if data["measurement_quality"] not in {"structured_nix_events", "job_wall_clock"}:
        raise ValueError("invalid measurement quality")
    if not nonempty(data["nix_version"]) or data["event_parser_version"] != "1":
        raise ValueError("invalid job producer versions")
    if data["event_parse_status"] not in {"events_observed", "no_events"}:
        raise ValueError("invalid event parse status")
    if not integer(data["total_duration_ms"]):
        raise ValueError("invalid job duration")


def validate_bundle(data: dict[str, Any], run: dict[str, Any]) -> None:
    require_keys(
        data,
        {
            "collection_status",
            "lane",
            "jobs",
            "missing_job_ids",
            "missing_fragments",
        },
        "bundle telemetry",
    )
    lane = data["lane"]
    if data["collection_status"] not in {"complete", "partial", "failed"}:
        raise ValueError("invalid bundle collection status")
    if lane is not None:
        validate_document(lane, "lane")
        if lane["run"] != run:
            raise ValueError("bundle lane belongs to another CI run")
    jobs = data["jobs"]
    if not isinstance(jobs, list):
        raise ValueError("invalid bundle jobs")
    for job in jobs:
        validate_document(job, "job")
        if job["run"] != run:
            raise ValueError("bundle job belongs to another CI run")
    missing_job_ids = string_list(data["missing_job_ids"], "missing job IDs")
    if not all(re.fullmatch(r"[0-9a-f]{64}", value) for value in missing_job_ids):
        raise ValueError("invalid missing job ID")
    missing_fragments = string_list(data["missing_fragments"], "missing fragments")
    if any(value != "lane" for value in missing_fragments):
        raise ValueError("invalid missing fragment name")
    if lane is None and "lane" not in missing_fragments:
        raise ValueError("missing lane is not declared")


def atomic_write_json(path: str | Path, value: object) -> None:
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        "w", encoding="utf-8", dir=target.parent, delete=False
    ) as output:
        output.write(canonical_json(value))
        output.write("\n")
        temporary = Path(output.name)
    temporary.replace(target)


def read_document(path: str | Path, expected_type: str | None = None) -> dict[str, Any]:
    with Path(path).open(encoding="utf-8") as source:
        value = json.load(source)
    validate_document(value, expected_type)
    return value
