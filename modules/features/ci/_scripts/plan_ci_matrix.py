#!/usr/bin/env python3

"""Produce a retrospective, workflow-wide Hestia matrix recommendation.

The planner deliberately writes a shadow recommendation only.  It consumes
completed telemetry, so its result cannot affect the source run.  A later live
adapter can reuse the same schedule contract after enough comparable runs have
made the cost model trustworthy.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import re
import shutil
import sys
from collections import defaultdict
from collections.abc import Iterable, Sequence
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from ci_telemetry import atomic_write_json, read_document, stable_hash
from ortools.sat.python import cp_model

SCHEMA_ID = "https://raw.githubusercontent.com/cons-tan-tan/dotfiles/main/modules/features/ci/_schemas/ci-optimization-v2.schema.json"
ALGORITHM = "cp-sat-set-union-load-balancing"
ALGORITHM_VERSION = "1"
PRODUCER = {"name": "dotfiles-ci-matrix-planner", "version": "1.0.0"}
STORE_DRV_PATTERN = re.compile(r"^/nix/store/[0-9a-z]{32}-(.+)\.drv$")


@dataclass(frozen=True)
class RunTelemetry:
    directory: Path
    index: dict[str, Any]
    bundles: dict[str, dict[str, Any]]


@dataclass(frozen=True)
class WorkUnit:
    unit_id: str
    system: str
    runner_labels: tuple[str, ...]
    member_check_ids: tuple[str, ...]
    display_names: tuple[str, ...]
    root_drv_ids: tuple[str, ...]
    dependency_drv_ids: frozenset[str]
    affinity_groups: tuple[str, ...]


@dataclass(frozen=True)
class Timing:
    sample_count: int
    observed_duration_ms: int
    workflow_queue_ms: int
    flake_start_ms: int
    flake_eval_ms: int
    evaluate_start_ms: dict[str, int]
    evaluate_ms: dict[str, int]
    dispatch_ms: dict[str, int]
    wrapper_overhead_ms: dict[str, tuple[int, ...]]


@dataclass(frozen=True)
class CostModel:
    dependency_cost_ms: dict[str, dict[str, int]]
    dependency_key_by_id: dict[str, dict[str, str]]
    default_dependency_cost_ms: dict[str, int]
    fixed_job_cost_ms: dict[str, int]
    sample_count_by_system: dict[str, int]
    dependency_sample_count_by_system: dict[str, dict[str, int]]

    def dependency_cost(self, system: str, drv_id: str) -> int:
        key = self.dependency_key_by_id[system][drv_id]
        return self.dependency_cost_ms[system].get(
            key, self.default_dependency_cost_ms[system]
        )


@dataclass(frozen=True)
class PlannedJob:
    name: str
    system: str
    runner_labels: tuple[str, ...]
    member_check_ids: tuple[str, ...]
    root_drv_ids: tuple[str, ...]
    dependency_drv_ids: tuple[str, ...]
    predicted_duration_ms: int


@dataclass(frozen=True)
class SolverResult:
    jobs: tuple[PlannedJob, ...]
    makespan_ms: int
    total_runner_ms: int
    stage_statuses: tuple[str, ...]
    wall_time_ms: int


class OptimizationUnavailable(RuntimeError):
    def __init__(self, statuses: Sequence[str]) -> None:
        super().__init__("matrix optimization produced no feasible solution")
        self.statuses = tuple(statuses)


def require_mapping(value: object, label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValueError(f"invalid {label}")
    return value


def require_nonempty_string(value: object, label: str) -> str:
    if not isinstance(value, str) or not value:
        raise ValueError(f"invalid {label}")
    return value


def require_nonnegative_integer(value: object, label: str) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value < 0:
        raise ValueError(f"invalid {label}")
    return value


def timestamp_ms(value: object, label: str) -> int:
    raw = require_nonempty_string(value, label)
    try:
        parsed = datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError as error:
        raise ValueError(f"invalid {label}") from error
    if parsed.tzinfo is None:
        raise ValueError(f"invalid {label}")
    return round(parsed.timestamp() * 1000)


def duration_ms(start: object, end: object, label: str) -> int:
    return max(
        0,
        timestamp_ms(end, f"{label} completion")
        - timestamp_ms(start, f"{label} start"),
    )


def quantile(values: Iterable[int], probability: float, *, default: int) -> int:
    ordered = sorted(value for value in values if value >= 0)
    if not ordered:
        return default
    index = max(0, math.ceil(probability * len(ordered)) - 1)
    return ordered[index]


def drv_name(path: str) -> str:
    match = STORE_DRV_PATTERN.fullmatch(path)
    if match is None:
        raise ValueError(f"invalid derivation path: {path}")
    return match.group(1)


def load_run(directory: Path) -> RunTelemetry:
    index_path = directory / "index.json"
    index = require_mapping(json.loads(index_path.read_text()), "run index")
    if (
        index.get("schema_version") != 1
        or index.get("document_type") != "run_index"
        or index.get("collection_status") != "complete"
    ):
        raise ValueError(f"run telemetry is not complete: {directory}")
    source = require_mapping(index.get("source"), "run source")
    if (
        source.get("conclusion") != "success"
        or source.get("trust_tier") != "trusted_default_branch"
    ):
        raise ValueError(f"run telemetry is not a successful trusted run: {directory}")

    bundles: dict[str, dict[str, Any]] = {}
    entries = index.get("systems")
    if not isinstance(entries, list) or not entries:
        raise ValueError("run index has no systems")
    for raw_entry in entries:
        entry = require_mapping(raw_entry, "system entry")
        system = require_nonempty_string(entry.get("system"), "system")
        path = require_nonempty_string(entry.get("bundle_path"), "bundle path")
        digest = require_nonempty_string(entry.get("bundle_sha256"), "bundle digest")
        if entry.get("bundle_collection_status") != "complete":
            raise ValueError(f"incomplete system telemetry: {system}")
        if (
            path != f"systems/{system}.json"
            or re.fullmatch(r"[0-9a-f]{64}", digest) is None
        ):
            raise ValueError(f"invalid system telemetry path: {system}")
        bundle_path = directory / path
        if hashlib.sha256(bundle_path.read_bytes()).hexdigest() != digest:
            raise ValueError(f"system telemetry digest mismatch: {system}")
        bundle = read_document(bundle_path, "bundle")
        expected_run = {
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
        if bundle.get("run") != expected_run:
            raise ValueError(f"system telemetry belongs to another run: {system}")
        bundle_data = require_mapping(bundle.get("data"), "bundle data")
        if bundle_data.get("collection_status") != "complete":
            raise ValueError(f"incomplete bundle telemetry: {system}")
        bundles[system] = bundle
    return RunTelemetry(directory=directory, index=index, bundles=bundles)


def discover_history(root: Path, target: Path, maximum_runs: int) -> list[RunTelemetry]:
    target_directory = target.resolve()
    candidates: list[Path] = [target_directory]
    if root.exists():
        candidates.extend(
            sorted(
                {
                    path.parent.resolve()
                    for path in root.rglob("index.json")
                    if path.parent.resolve() != target_directory
                }
            )
        )
    runs: list[RunTelemetry] = []
    seen: set[tuple[str, int]] = set()
    for directory in candidates:
        try:
            run = load_run(directory)
        except (
            KeyError,
            RecursionError,
            UnicodeError,
            OSError,
            json.JSONDecodeError,
            ValueError,
        ):
            continue
        source = require_mapping(run.index["source"], "run source")
        identity = (
            require_nonempty_string(source.get("run_id"), "source run id"),
            require_nonnegative_integer(
                source.get("run_attempt"), "source run attempt"
            ),
        )
        if identity in seen:
            continue
        seen.add(identity)
        runs.append(run)

    def creation(run: RunTelemetry) -> int:
        try:
            return timestamp_ms(
                require_mapping(run.index["source"], "run source").get("created_at"),
                "source creation",
            )
        except ValueError:
            return 0

    runs.sort(key=creation, reverse=True)
    target_run = next(
        (run for run in runs if run.directory.resolve() == target_directory), None
    )
    if target_run is None:
        raise ValueError("target run is not usable telemetry")
    return [target_run] + [run for run in runs if run is not target_run][
        : maximum_runs - 1
    ]


def lane_document(bundle: dict[str, Any]) -> dict[str, Any]:
    data = require_mapping(bundle.get("data"), "bundle data")
    lane = require_mapping(data.get("lane"), "lane document")
    return lane


def dependency_names(bundle: dict[str, Any]) -> dict[str, str]:
    lane_data = require_mapping(lane_document(bundle).get("data"), "lane data")
    result: dict[str, str] = {}
    derivations = lane_data.get("derivations")
    if not isinstance(derivations, list):
        raise ValueError("invalid lane derivations")
    for raw in derivations:
        item = require_mapping(raw, "derivation")
        identity = require_nonempty_string(item.get("drv_id"), "derivation id")
        name = drv_name(
            require_nonempty_string(item.get("drv_path"), "derivation path")
        )
        previous = result.get(identity)
        if previous is not None and previous != name:
            raise ValueError("derivation identity collision")
        result[identity] = name
    return result


def target_units(
    target: RunTelemetry,
) -> tuple[list[WorkUnit], dict[str, dict[str, str]]]:
    units: list[WorkUnit] = []
    keys_by_system: dict[str, dict[str, str]] = {}
    for system, bundle in sorted(target.bundles.items()):
        keys_by_system[system] = dependency_names(bundle)
        lane_data = require_mapping(lane_document(bundle).get("data"), "lane data")
        checks = lane_data.get("checks")
        if not isinstance(checks, list):
            raise ValueError("invalid lane checks")
        grouped: dict[str, list[dict[str, Any]]] = defaultdict(list)
        for raw in checks:
            check = require_mapping(raw, "check")
            plan = require_mapping(check.get("plan"), "check plan")
            if (
                check.get("selection") == "scheduled"
                and plan.get("status") == "success"
            ):
                grouped[
                    require_nonempty_string(check.get("drv_id"), "check drv id")
                ].append(check)
        if not grouped and any(
            require_mapping(raw, "check").get("selection") == "scheduled"
            for raw in checks
        ):
            raise ValueError(f"scheduled checks have no successful plans: {system}")
        for root_id, members in sorted(grouped.items()):
            labels = {
                tuple(
                    require_nonempty_string(label, "runner label")
                    for label in check["runner_labels"]
                )
                for check in members
            }
            if len(labels) != 1 or not next(iter(labels)):
                raise ValueError("one root derivation has incompatible runner labels")
            dependencies = frozenset(
                dependency
                for check in members
                for dependency in require_mapping(check["plan"], "check plan")[
                    "dependency_drv_ids"
                ]
            )
            unknown = dependencies - keys_by_system[system].keys()
            if unknown:
                raise ValueError(
                    "check plan references derivations without semantic names"
                )
            check_ids = tuple(sorted(str(check["check_id"]) for check in members))
            affinity = tuple(
                sorted(
                    {
                        str(check["static_affinity_group"])
                        for check in members
                        if check.get("static_affinity_group") is not None
                    }
                )
            )
            units.append(
                WorkUnit(
                    unit_id=stable_hash([system, root_id, *check_ids]),
                    system=system,
                    runner_labels=next(iter(labels)),
                    member_check_ids=check_ids,
                    display_names=tuple(
                        sorted(str(check["display_name"]) for check in members)
                    ),
                    root_drv_ids=(root_id,),
                    dependency_drv_ids=dependencies,
                    affinity_groups=affinity,
                )
            )
    runner_classes: dict[str, set[tuple[str, ...]]] = defaultdict(set)
    for unit in units:
        runner_classes[unit.system].add(unit.runner_labels)
    unsupported = sorted(
        system for system, labels in runner_classes.items() if len(labels) != 1
    )
    if unsupported:
        raise ValueError(
            "multiple runner classes are not yet modeled for: " + ", ".join(unsupported)
        )
    return units, keys_by_system


def jobs_by_id(
    bundle: dict[str, Any],
) -> tuple[dict[str, dict[str, Any]], dict[str, dict[str, Any]]]:
    data = require_mapping(bundle.get("data"), "bundle data")
    lane_data = require_mapping(lane_document(bundle).get("data"), "lane data")
    decision = require_mapping(lane_data.get("decision"), "lane decision")
    decisions = {
        str(item["job_id"]): require_mapping(item, "decision job")
        for item in decision.get("jobs", [])
    }
    observed = {
        str(require_mapping(job.get("data"), "job data")["job_id"]): require_mapping(
            job.get("data"), "job data"
        )
        for job in data.get("jobs", [])
    }
    return decisions, observed


def runner_classes(run: RunTelemetry) -> dict[str, frozenset[tuple[str, ...]]]:
    result: dict[str, frozenset[tuple[str, ...]]] = {}
    for system, bundle in run.bundles.items():
        decisions, _observed = jobs_by_id(bundle)
        result[system] = frozenset(
            tuple(
                require_nonempty_string(label, "runner label")
                for label in decision.get("runner_labels", [])
            )
            for decision in decisions.values()
        )
    return result


def compatible_history(
    history: Sequence[RunTelemetry], target: RunTelemetry
) -> list[RunTelemetry]:
    target_classes = runner_classes(target)
    result = []
    for run in history:
        try:
            if runner_classes(run) == target_classes:
                result.append(run)
        except (KeyError, TypeError, ValueError):
            continue
    return result


def build_cost_model(
    history: Sequence[RunTelemetry],
    target_keys: dict[str, dict[str, str]],
    target_runner_labels: dict[str, tuple[str, ...]],
    timing: Timing,
    robust_quantile: float,
) -> CostModel:
    dependency_samples: dict[str, dict[str, list[int]]] = defaultdict(
        lambda: defaultdict(list)
    )
    fixed_samples: dict[str, list[int]] = defaultdict(list)
    sample_counts: dict[str, int] = defaultdict(int)
    for run in history:
        for system, bundle in run.bundles.items():
            names = dependency_names(bundle)
            decisions, observed = jobs_by_id(bundle)
            for job_id, decision in decisions.items():
                labels = tuple(
                    require_nonempty_string(label, "runner label")
                    for label in decision.get("runner_labels", [])
                )
                if labels != target_runner_labels.get(system):
                    continue
                job = observed.get(job_id)
                if job is None or job.get("status") != "success":
                    continue
                phases = require_mapping(job.get("phases"), "job phases")
                setup = require_mapping(phases.get("github_job_setup"), "setup phase")
                prefetch = require_mapping(phases.get("prefetch"), "prefetch phase")
                build = require_mapping(phases.get("nix_build"), "build phase")
                fixed_samples[system].append(
                    require_nonnegative_integer(
                        setup.get("duration_ms"), "setup duration"
                    )
                )
                planned = [str(value) for value in decision.get("planned_drv_ids", [])]
                if not planned:
                    continue
                event_weights: dict[str, int] = defaultdict(int)
                for raw_event in job.get("derivation_events", []):
                    event = require_mapping(raw_event, "derivation event")
                    if event.get("outcome") == "completed":
                        event_weights[str(event["drv_id"])] += max(
                            1,
                            require_nonnegative_integer(
                                event.get("duration_ms"), "derivation duration"
                            ),
                        )
                weights = {
                    identity: max(1, event_weights.get(identity, 0))
                    for identity in planned
                }
                total_weight = sum(weights.values())
                build_duration = require_nonnegative_integer(
                    build.get("duration_ms"), "build duration"
                )
                prefetch_duration = require_nonnegative_integer(
                    prefetch.get("duration_ms"), "prefetch duration"
                )
                for identity in planned:
                    name = names.get(identity)
                    if name is None:
                        continue
                    allocated = round(build_duration * weights[identity] / total_weight)
                    allocated += round(prefetch_duration / len(planned))
                    dependency_samples[system][name].append(max(1, allocated))
                    sample_counts[system] += 1

    dependency_cost: dict[str, dict[str, int]] = {}
    defaults: dict[str, int] = {}
    fixed: dict[str, int] = {}
    for system, target in target_keys.items():
        all_samples = [
            value
            for values in dependency_samples.get(system, {}).values()
            for value in values
        ]
        defaults[system] = max(1, quantile(all_samples, robust_quantile, default=1_000))
        dependency_cost[system] = {
            key: max(
                1,
                quantile(
                    dependency_samples[system].get(key, []),
                    robust_quantile,
                    default=defaults[system],
                ),
            )
            for key in set(target.values())
        }
        wrapper = timing.wrapper_overhead_ms.get(system, ())
        fixed[system] = max(
            1,
            quantile(fixed_samples.get(system, []), robust_quantile, default=5_000)
            + quantile(wrapper, robust_quantile, default=0),
        )
    return CostModel(
        dependency_cost_ms=dependency_cost,
        dependency_key_by_id=target_keys,
        default_dependency_cost_ms=defaults,
        fixed_job_cost_ms=fixed,
        sample_count_by_system=dict(sample_counts),
        dependency_sample_count_by_system={
            system: {
                key: len(values)
                for key, values in dependency_samples.get(system, {}).items()
            }
            for system in target_keys
        },
    )


def parse_timing(path: Path, target: RunTelemetry) -> Timing:
    value = require_mapping(json.loads(path.read_text()), "workflow timing")
    if value.get("schema_version") not in {1, 2}:
        raise ValueError("unsupported workflow timing")
    source = require_mapping(target.index.get("source"), "run source")
    if (
        str(value.get("run_id")) != str(source.get("run_id"))
        or value.get("run_attempt") != source.get("run_attempt")
        or value.get("repository") != source.get("repository")
        or value.get("commit_sha") != source.get("head_sha")
    ):
        raise ValueError("workflow timing belongs to another run")
    raw_jobs = value.get("jobs")
    if not isinstance(raw_jobs, list):
        raise ValueError("workflow timing has no jobs")
    workflow_start = timestamp_ms(value.get("started_at"), "workflow start")
    observed_duration = duration_ms(
        source.get("created_at"), source.get("updated_at"), "workflow"
    )
    if value.get("schema_version") == 2:
        return parse_structured_timing(
            raw_jobs,
            target,
            observed_duration=observed_duration,
            workflow_start=workflow_start,
            workflow_created=timestamp_ms(
                source.get("created_at"), "workflow creation"
            ),
        )
    return parse_legacy_timing(
        raw_jobs,
        target,
        observed_duration=observed_duration,
        workflow_start=workflow_start,
        workflow_created=timestamp_ms(source.get("created_at"), "workflow creation"),
    )


def parse_structured_timing(
    raw_jobs: list[object],
    target: RunTelemetry,
    *,
    observed_duration: int,
    workflow_start: int,
    workflow_created: int,
) -> Timing:
    jobs = [require_mapping(raw, "workflow job") for raw in raw_jobs]

    def select(role: str, system: str | None = None) -> list[dict[str, Any]]:
        return [
            job
            for job in jobs
            if job.get("role") == role
            and (system is None or job.get("system") == system)
        ]

    def exactly_one(role: str, system: str) -> dict[str, Any]:
        matches = select(role, system)
        if len(matches) != 1:
            raise ValueError(f"expected one {role} workflow job for {system}")
        return matches[0]

    flake_jobs = select("flake-eval")
    if not flake_jobs:
        raise ValueError("workflow timing has no flake evaluation jobs")
    flake_started = min(
        timestamp_ms(job.get("started_at"), "flake evaluation start")
        for job in flake_jobs
    )
    flake_completed = max(
        timestamp_ms(job.get("completed_at"), "flake evaluation completion")
        for job in flake_jobs
    )
    evaluate: dict[str, int] = {}
    evaluate_start: dict[str, int] = {}
    dispatch: dict[str, int] = {}
    wrapper: dict[str, tuple[int, ...]] = {}
    for system in sorted(target.bundles):
        evaluate_job = exactly_one("system-evaluate", system)
        evaluate_start[system] = max(
            0,
            timestamp_ms(evaluate_job.get("started_at"), "system evaluation start")
            - workflow_start,
        )
        evaluate[system] = duration_ms(
            evaluate_job.get("started_at"),
            evaluate_job.get("completed_at"),
            "system evaluation",
        )
        evaluate_completed = timestamp_ms(
            evaluate_job.get("completed_at"), "system evaluation completion"
        )
        build_jobs = select("system-build", system)
        dispatch[system] = (
            max(
                0,
                max(
                    timestamp_ms(job.get("started_at"), "build start")
                    for job in build_jobs
                )
                - evaluate_completed,
            )
            if build_jobs
            else 0
        )
        timing_by_key = {
            require_nonempty_string(
                job.get("telemetry_key"), "build telemetry key"
            ): job
            for job in build_jobs
        }
        if len(timing_by_key) != len(build_jobs):
            raise ValueError("duplicate build timing identity")
        _decisions, observed = jobs_by_id(target.bundles[system])
        observed_by_key = {
            require_nonempty_string(job.get("telemetry_key"), "job telemetry key"): job
            for job in observed.values()
        }
        if set(timing_by_key) != set(observed_by_key):
            raise ValueError(f"build timing does not match telemetry for {system}")
        wrapper[system] = tuple(
            max(
                0,
                duration_ms(
                    timing_by_key[key].get("started_at"),
                    timing_by_key[key].get("completed_at"),
                    "build workflow job",
                )
                - require_nonnegative_integer(
                    observed_by_key[key].get("total_duration_ms"), "job duration"
                ),
            )
            for key in sorted(timing_by_key)
        )
    return Timing(
        sample_count=1,
        observed_duration_ms=observed_duration,
        workflow_queue_ms=max(0, workflow_start - workflow_created),
        flake_start_ms=max(0, flake_started - workflow_start),
        flake_eval_ms=max(0, flake_completed - flake_started),
        evaluate_start_ms=evaluate_start,
        evaluate_ms=evaluate,
        dispatch_ms=dispatch,
        wrapper_overhead_ms=wrapper,
    )


def parse_legacy_timing(
    raw_jobs: list[object],
    target: RunTelemetry,
    *,
    observed_duration: int,
    workflow_start: int,
    workflow_created: int,
) -> Timing:
    jobs = {
        require_nonempty_string(job.get("name"), "workflow job name"): job
        for raw in raw_jobs
        for job in [require_mapping(raw, "workflow job")]
    }
    if len(jobs) != len(raw_jobs):
        raise ValueError("duplicate workflow job name")

    def job_duration(name: str) -> int:
        job = require_mapping(jobs.get(name), f"workflow job {name}")
        return duration_ms(job.get("started_at"), job.get("completed_at"), name)

    def job_start(name: str) -> int:
        job = require_mapping(jobs.get(name), f"workflow job {name}")
        return timestamp_ms(job.get("started_at"), f"workflow job {name} start")

    def job_completion(name: str) -> int:
        job = require_mapping(jobs.get(name), f"workflow job {name}")
        return timestamp_ms(job.get("completed_at"), f"workflow job {name} completion")

    lane_names: dict[str, str] = {}
    for system in sorted(target.bundles):
        structured_lane = f"system / {system}"
        if f"{structured_lane} / evaluate" in jobs:
            lane_names[system] = structured_lane
            continue
        conventional = (
            "linux"
            if system.endswith("linux")
            else "darwin"
            if system.endswith("darwin")
            else system
        )
        if f"{conventional} / evaluate" not in jobs:
            raise ValueError(f"could not identify workflow lane for {system}")
        lane_names[system] = conventional

    flake_names = (
        ["evaluate / flake"]
        if "evaluate / flake" in jobs
        else sorted(
            name
            for name in jobs
            if name.startswith("flake / ") and name.endswith(" / evaluate")
        )
    )
    if not flake_names:
        raise ValueError("workflow timing has no flake evaluation jobs")
    flake_started = min(job_start(name) for name in flake_names)
    flake_completed = max(job_completion(name) for name in flake_names)
    evaluate: dict[str, int] = {}
    evaluate_start: dict[str, int] = {}
    dispatch: dict[str, int] = {}
    wrapper: dict[str, tuple[int, ...]] = {}
    for system, lane_name in lane_names.items():
        evaluate_name = f"{lane_name} / evaluate"
        evaluate_start[system] = max(0, job_start(evaluate_name) - workflow_start)
        evaluate[system] = job_duration(evaluate_name)
        evaluate_completed = job_completion(evaluate_name)
        build_names = [
            name
            for name in jobs
            if name.startswith(f"{lane_name} / build / ")
            and (lane_name.startswith("system / ") or name.endswith(f" ({system})"))
        ]
        dispatch[system] = (
            max(0, max(job_start(name) for name in build_names) - evaluate_completed)
            if build_names
            else 0
        )
        _decisions, observed = jobs_by_id(target.bundles[system])
        extras = []
        for job in observed.values():
            name = str(job["name"])
            candidates = (
                [f"{lane_name} / build / {name}"]
                if lane_name.startswith("system / ")
                else [f"{lane_name} / build / {name} ({system})"]
            )
            workflow_name = next(
                (candidate for candidate in candidates if candidate in jobs), None
            )
            if workflow_name is None:
                continue
            extras.append(
                max(
                    0,
                    job_duration(workflow_name)
                    - require_nonnegative_integer(
                        job.get("total_duration_ms"), "job duration"
                    ),
                )
            )
        wrapper[system] = tuple(extras)
    return Timing(
        sample_count=1,
        observed_duration_ms=observed_duration,
        workflow_queue_ms=max(0, workflow_start - workflow_created),
        flake_start_ms=max(0, flake_started - workflow_start),
        flake_eval_ms=max(0, flake_completed - flake_started),
        evaluate_start_ms=evaluate_start,
        evaluate_ms=evaluate,
        dispatch_ms=dispatch,
        wrapper_overhead_ms=wrapper,
    )


def aggregate_timing(
    target: Timing, samples: Sequence[Timing], robust_quantile: float
) -> Timing:
    usable = [
        timing
        for timing in samples
        if set(timing.evaluate_ms) == set(target.evaluate_ms)
    ]
    if not usable:
        usable = [target]
    systems = sorted(target.evaluate_ms)
    return Timing(
        sample_count=len(usable),
        observed_duration_ms=target.observed_duration_ms,
        workflow_queue_ms=quantile(
            (timing.workflow_queue_ms for timing in usable),
            robust_quantile,
            default=target.workflow_queue_ms,
        ),
        flake_start_ms=quantile(
            (timing.flake_start_ms for timing in usable),
            robust_quantile,
            default=target.flake_start_ms,
        ),
        flake_eval_ms=quantile(
            (timing.flake_eval_ms for timing in usable),
            robust_quantile,
            default=target.flake_eval_ms,
        ),
        evaluate_start_ms={
            system: quantile(
                (timing.evaluate_start_ms[system] for timing in usable),
                robust_quantile,
                default=target.evaluate_start_ms[system],
            )
            for system in systems
        },
        evaluate_ms={
            system: quantile(
                (timing.evaluate_ms[system] for timing in usable),
                robust_quantile,
                default=target.evaluate_ms[system],
            )
            for system in systems
        },
        dispatch_ms={
            system: quantile(
                (timing.dispatch_ms[system] for timing in usable),
                robust_quantile,
                default=target.dispatch_ms[system],
            )
            for system in systems
        },
        wrapper_overhead_ms={
            system: tuple(
                value
                for timing in usable
                for value in timing.wrapper_overhead_ms.get(system, ())
            )
            for system in systems
        },
    )


def predicted_job_duration(
    system: str, dependencies: Iterable[str], costs: CostModel
) -> int:
    return costs.fixed_job_cost_ms[system] + sum(
        costs.dependency_cost(system, identity) for identity in set(dependencies)
    )


def baseline_jobs(target: RunTelemetry, costs: CostModel) -> list[PlannedJob]:
    result: list[PlannedJob] = []
    for system, bundle in sorted(target.bundles.items()):
        decisions, _observed = jobs_by_id(bundle)
        for decision in decisions.values():
            dependencies = tuple(
                sorted(str(value) for value in decision["planned_drv_ids"])
            )
            result.append(
                PlannedJob(
                    name=str(decision["name"]),
                    system=system,
                    runner_labels=tuple(
                        str(value) for value in decision["runner_labels"]
                    ),
                    member_check_ids=tuple(
                        str(value) for value in decision["member_check_ids"]
                    ),
                    root_drv_ids=tuple(
                        str(value) for value in decision["root_drv_ids"]
                    ),
                    dependency_drv_ids=dependencies,
                    predicted_duration_ms=predicted_job_duration(
                        system, dependencies, costs
                    ),
                )
            )
    return result


def schedule_metrics(jobs: Sequence[PlannedJob], timing: Timing) -> tuple[int, int]:
    lane_finishes = []
    for system in timing.evaluate_ms:
        maximum = max(
            (job.predicted_duration_ms for job in jobs if job.system == system),
            default=0,
        )
        lane_finishes.append(
            timing.evaluate_start_ms[system]
            + timing.evaluate_ms[system]
            + timing.dispatch_ms[system]
            + maximum
        )
    return timing.workflow_queue_ms + max(
        [timing.flake_start_ms + timing.flake_eval_ms, *lane_finishes]
    ), sum(job.predicted_duration_ms for job in jobs)


def status_name(status: int) -> str:
    return {
        cp_model.OPTIMAL: "optimal",
        cp_model.FEASIBLE: "feasible",
        cp_model.INFEASIBLE: "infeasible",
        cp_model.MODEL_INVALID: "model_invalid",
        cp_model.UNKNOWN: "unknown",
    }.get(status, f"status_{status}")


def solve_schedule(
    units: Sequence[WorkUnit],
    costs: CostModel,
    timing: Timing,
    *,
    max_jobs_per_system: int,
    makespan_slack_ms: int,
    time_limit_seconds: float,
) -> SolverResult:
    if not units:
        critical, _total = schedule_metrics((), timing)
        return SolverResult((), critical, 0, ("not_needed",), 0)
    model = cp_model.CpModel()
    classes = sorted({(unit.system, unit.runner_labels) for unit in units})
    bins = {
        key: tuple(
            range(
                min(
                    max_jobs_per_system,
                    sum(
                        1 for unit in units if (unit.system, unit.runner_labels) == key
                    ),
                )
            )
        )
        for key in classes
    }
    x: dict[tuple[int, int], Any] = {}
    used: dict[tuple[str, tuple[str, ...], int], Any] = {}
    loads: dict[tuple[str, tuple[str, ...], int], Any] = {}
    load_upper_bounds: dict[tuple[str, tuple[str, ...], int], int] = {}
    units_by_class: dict[tuple[str, tuple[str, ...]], list[int]] = defaultdict(list)
    for index, unit in enumerate(units):
        units_by_class[(unit.system, unit.runner_labels)].append(index)

    for key, indexes in units_by_class.items():
        system, labels = key
        for position in bins[key]:
            used[(system, labels, position)] = model.NewBoolVar(
                f"used_{system}_{position}_{stable_hash(labels)[:8]}"
            )
            for index in indexes:
                x[(index, position)] = model.NewBoolVar(f"assign_{index}_{position}")
                model.Add(x[(index, position)] <= used[(system, labels, position)])
        for index in indexes:
            model.Add(sum(x[(index, position)] for position in bins[key]) == 1)
        for left, right in zip(bins[key], bins[key][1:]):
            model.Add(used[(system, labels, left)] >= used[(system, labels, right)])

    for system in sorted({unit.system for unit in units}):
        model.Add(
            sum(
                variable
                for (candidate, _labels, _position), variable in used.items()
                if candidate == system
            )
            <= max_jobs_per_system
        )

    for key, indexes in units_by_class.items():
        system, labels = key
        dependencies = sorted(
            {
                dependency
                for index in indexes
                for dependency in units[index].dependency_drv_ids
            }
        )
        upper = costs.fixed_job_cost_ms[system] + sum(
            costs.dependency_cost(system, dependency) for dependency in dependencies
        )
        for position in bins[key]:
            dependency_vars = []
            for dependency in dependencies:
                z = model.NewBoolVar(
                    f"dep_{system}_{position}_{dependency[:10]}_{stable_hash(labels)[:6]}"
                )
                consumers = [
                    x[(index, position)]
                    for index in indexes
                    if dependency in units[index].dependency_drv_ids
                ]
                for consumer in consumers:
                    model.Add(z >= consumer)
                model.Add(z <= sum(consumers))
                dependency_vars.append((dependency, z))
            load = model.NewIntVar(
                0, upper, f"load_{system}_{position}_{stable_hash(labels)[:8]}"
            )
            model.Add(
                load
                == costs.fixed_job_cost_ms[system] * used[(system, labels, position)]
                + sum(
                    costs.dependency_cost(system, dependency) * variable
                    for dependency, variable in dependency_vars
                )
            )
            loads[(system, labels, position)] = load
            load_upper_bounds[(system, labels, position)] = upper

    max_upper = max(
        timing.workflow_queue_ms + timing.flake_start_ms + timing.flake_eval_ms,
        *(
            timing.workflow_queue_ms
            + timing.evaluate_start_ms[system]
            + timing.evaluate_ms[system]
            + timing.dispatch_ms[system]
            + sum(upper for key, upper in load_upper_bounds.items() if key[0] == system)
            for system in timing.evaluate_ms
        ),
    )
    lane_max: dict[str, Any] = {}
    lane_finish: dict[str, Any] = {}
    for system in sorted(timing.evaluate_ms):
        system_loads = [load for key, load in loads.items() if key[0] == system]
        upper = sum(
            value for key, value in load_upper_bounds.items() if key[0] == system
        )
        lane_max[system] = model.NewIntVar(0, upper, f"lane_max_{system}")
        model.AddMaxEquality(lane_max[system], system_loads or [0])
        offset = (
            timing.workflow_queue_ms
            + timing.evaluate_start_ms[system]
            + timing.evaluate_ms[system]
            + timing.dispatch_ms[system]
        )
        lane_finish[system] = model.NewIntVar(
            offset, offset + upper, f"lane_finish_{system}"
        )
        model.Add(lane_finish[system] == offset + lane_max[system])
    makespan = model.NewIntVar(0, max_upper, "workflow_makespan")
    model.AddMaxEquality(
        makespan,
        [
            timing.workflow_queue_ms + timing.flake_start_ms + timing.flake_eval_ms,
            *lane_finish.values(),
        ],
    )
    total_runner = model.NewIntVar(0, sum(load_upper_bounds.values()), "total_runner")
    model.Add(total_runner == sum(loads.values()))

    affinity_members: dict[tuple[str, str], list[int]] = defaultdict(list)
    for index, unit in enumerate(units):
        for group in unit.affinity_groups:
            affinity_members[(unit.system, group)].append(index)
    separations = []
    for (_system, _group), indexes in affinity_members.items():
        for offset, left in enumerate(indexes):
            for right in indexes[offset + 1 :]:
                if units[left].runner_labels != units[right].runner_labels:
                    continue
                key = (units[left].system, units[left].runner_labels)
                together_vars = []
                for position in bins[key]:
                    together = model.NewBoolVar(f"together_{left}_{right}_{position}")
                    model.Add(together <= x[(left, position)])
                    model.Add(together <= x[(right, position)])
                    model.Add(
                        together >= x[(left, position)] + x[(right, position)] - 1
                    )
                    together_vars.append(together)
                separated = model.NewBoolVar(f"separated_{left}_{right}")
                model.Add(separated + sum(together_vars) == 1)
                separations.append(separated)

    budgets = [
        time_limit_seconds * 0.5,
        time_limit_seconds * 0.3,
        time_limit_seconds * 0.2,
    ]
    statuses: list[str] = []
    wall_time = 0.0

    def solve(objective: Any, budget: float) -> tuple[Any, int]:
        model.Minimize(objective)
        solver = cp_model.CpSolver()
        solver.parameters.max_time_in_seconds = max(0.05, budget)
        solver.parameters.num_search_workers = 1
        solver.parameters.random_seed = 0
        status = solver.Solve(model)
        return solver, status

    solver, status = solve(makespan, budgets[0])
    statuses.append(status_name(status))
    wall_time += solver.WallTime()
    if status not in {cp_model.OPTIMAL, cp_model.FEASIBLE}:
        raise OptimizationUnavailable(statuses)
    primary_solver = solver
    best_makespan = solver.Value(makespan)
    model.Add(makespan <= best_makespan + makespan_slack_ms)

    runner_solver, status = solve(total_runner, budgets[1])
    statuses.append(status_name(status))
    wall_time += runner_solver.WallTime()
    final_solver = primary_solver
    if status in {cp_model.OPTIMAL, cp_model.FEASIBLE}:
        best_total = runner_solver.Value(total_runner)
        model.Add(total_runner <= best_total)
        final_solver = runner_solver

        stability = sum(separations) if separations else 0
        stability_solver, status = solve(stability, budgets[2])
        statuses.append(status_name(status))
        wall_time += stability_solver.WallTime()
        if status in {cp_model.OPTIMAL, cp_model.FEASIBLE}:
            final_solver = stability_solver

    planned: list[PlannedJob] = []
    numbering: dict[str, int] = defaultdict(int)
    for key in classes:
        system, labels = key
        indexes = units_by_class[key]
        for position in bins[key]:
            members = [
                index for index in indexes if final_solver.Value(x[(index, position)])
            ]
            if not members:
                continue
            numbering[system] += 1
            display = sorted(
                {name for index in members for name in units[index].display_names}
            )
            suffix = (
                re.sub(r"[^a-zA-Z0-9_-]+", "-", display[0])[:36]
                if display
                else "checks"
            )
            dependencies = tuple(
                sorted(
                    {
                        dependency
                        for index in members
                        for dependency in units[index].dependency_drv_ids
                    }
                )
            )
            planned.append(
                PlannedJob(
                    name=f"optimized-{numbering[system]:02d}-{suffix}",
                    system=system,
                    runner_labels=labels,
                    member_check_ids=tuple(
                        sorted(
                            {
                                identity
                                for index in members
                                for identity in units[index].member_check_ids
                            }
                        )
                    ),
                    root_drv_ids=tuple(
                        sorted(
                            {
                                identity
                                for index in members
                                for identity in units[index].root_drv_ids
                            }
                        )
                    ),
                    dependency_drv_ids=dependencies,
                    predicted_duration_ms=final_solver.Value(
                        loads[(system, labels, position)]
                    ),
                )
            )
    return SolverResult(
        jobs=tuple(sorted(planned, key=lambda item: (item.system, item.name))),
        makespan_ms=final_solver.Value(makespan),
        total_runner_ms=final_solver.Value(total_runner),
        stage_statuses=tuple(statuses),
        wall_time_ms=round(wall_time * 1000),
    )


def job_json(job: PlannedJob) -> dict[str, object]:
    return {
        "name": job.name,
        "system": job.system,
        "runner_labels": list(job.runner_labels),
        "member_check_ids": list(job.member_check_ids),
        "root_drv_ids": list(job.root_drv_ids),
        "planned_drv_ids": list(job.dependency_drv_ids),
        "predicted_duration_ms": job.predicted_duration_ms,
    }


def schedule_json(jobs: Sequence[PlannedJob], timing: Timing) -> dict[str, object]:
    critical, total = schedule_metrics(jobs, timing)
    systems = []
    for system in sorted(timing.evaluate_ms):
        system_jobs = sorted(
            (job for job in jobs if job.system == system), key=lambda item: item.name
        )
        systems.append(
            {
                "system": system,
                "predicted_lane_duration_ms": timing.evaluate_ms[system]
                + timing.workflow_queue_ms
                + timing.evaluate_start_ms[system]
                + timing.dispatch_ms[system]
                + max((job.predicted_duration_ms for job in system_jobs), default=0),
                "jobs": [job_json(job) for job in system_jobs],
            }
        )
    return {
        "predicted_workflow_duration_ms": critical,
        "critical_path_ms": critical,
        "total_build_runner_ms": total,
        "job_count": len(jobs),
        "systems": systems,
    }


def observed_at() -> str:
    return (
        datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
    )


def create_plan(
    *,
    target: RunTelemetry,
    history: Sequence[RunTelemetry],
    timing: Timing,
    max_jobs_per_system: int,
    makespan_slack_ms: int,
    solver_time_limit_seconds: float,
    robust_quantile: float,
    minimum_history_runs: int,
    minimum_dependency_samples: int,
) -> dict[str, object]:
    units, target_keys = target_units(target)
    target_runner_labels = {unit.system: unit.runner_labels for unit in units}
    costs = build_cost_model(
        history,
        target_keys,
        target_runner_labels,
        timing,
        robust_quantile,
    )
    baseline = baseline_jobs(target, costs)
    try:
        solution = solve_schedule(
            units,
            costs,
            timing,
            max_jobs_per_system=max_jobs_per_system,
            makespan_slack_ms=makespan_slack_ms,
            time_limit_seconds=solver_time_limit_seconds,
        )
    except OptimizationUnavailable as error:
        critical, total = schedule_metrics(baseline, timing)
        solution = SolverResult(
            jobs=tuple(baseline),
            makespan_ms=critical,
            total_runner_ms=total,
            stage_statuses=(*error.statuses, "fallback_baseline"),
            wall_time_ms=0,
        )
    baseline_data = schedule_json(baseline, timing)
    recommendation = schedule_json(solution.jobs, timing)
    source = require_mapping(target.index["source"], "run source")
    history_samples = sorted(
        (
            {
                "run_id": str(
                    require_mapping(run.index["source"], "run source")["run_id"]
                ),
                "run_attempt": require_nonnegative_integer(
                    require_mapping(run.index["source"], "run source").get(
                        "run_attempt"
                    ),
                    "source run attempt",
                ),
            }
            for run in history
        ),
        key=lambda item: (str(item["run_id"]), int(item["run_attempt"])),
    )
    target_cost_keys: dict[str, set[str]] = defaultdict(set)
    for unit in units:
        target_cost_keys[unit.system].update(
            target_keys[unit.system][identity] for identity in unit.dependency_drv_ids
        )
    qualified_cost_keys = {
        system: {
            key
            for key, count in costs.dependency_sample_count_by_system.get(
                system, {}
            ).items()
            if count >= minimum_dependency_samples
        }
        for system in target_cost_keys
    }
    coverage_complete = all(
        keys.issubset(qualified_cost_keys.get(system, set()))
        for system, keys in target_cost_keys.items()
    )
    usable_sample_count = min(len(history), timing.sample_count)
    data_ready, reason_code = rollout_decision(
        has_work=bool(units),
        usable_sample_count=usable_sample_count,
        minimum_history_runs=minimum_history_runs,
        coverage_complete=coverage_complete,
        stage_statuses=solution.stage_statuses,
    )
    return {
        "$schema": SCHEMA_ID,
        "schema_version": 2,
        "document_type": "ci_matrix_optimization",
        "producer": PRODUCER,
        "observed_at": observed_at(),
        "source": {
            "repository": source["repository"],
            "run_id": source["run_id"],
            "run_attempt": source["run_attempt"],
            "commit_sha": source["head_sha"],
            "history_samples": history_samples,
            "usable_history_runs": len(history),
        },
        "rollout": {
            "mode": "shadow",
            "minimum_history_runs": minimum_history_runs,
            "data_ready": data_ready,
            "automatic_application": False,
            "reason_code": reason_code,
        },
        "model": {
            "algorithm": ALGORITHM,
            "algorithm_version": ALGORITHM_VERSION,
            "parameters": {
                "max_jobs_per_system": max_jobs_per_system,
                "makespan_slack_ms": makespan_slack_ms,
                "solver_time_limit_seconds": solver_time_limit_seconds,
                "robust_quantile": robust_quantile,
                "minimum_dependency_samples": minimum_dependency_samples,
            },
            "costs": {
                system: {
                    "fixed_job_cost_ms": costs.fixed_job_cost_ms[system],
                    "default_dependency_cost_ms": costs.default_dependency_cost_ms[
                        system
                    ],
                    "dependency_samples": costs.sample_count_by_system.get(system, 0),
                    "target_dependency_count": len(target_cost_keys.get(system, set())),
                    "qualified_dependency_count": len(
                        target_cost_keys.get(system, set())
                        & qualified_cost_keys.get(system, set())
                    ),
                }
                for system in sorted(costs.fixed_job_cost_ms)
            },
            "solver": {
                "stage_statuses": list(solution.stage_statuses),
                "wall_time_ms": solution.wall_time_ms,
            },
        },
        "workflow_timing": {
            "sample_count": timing.sample_count,
            "observed_duration_ms": timing.observed_duration_ms,
            "workflow_queue_ms": timing.workflow_queue_ms,
            "flake_start_ms": timing.flake_start_ms,
            "flake_eval_ms": timing.flake_eval_ms,
            "systems": {
                system: {
                    "evaluate_start_ms": timing.evaluate_start_ms[system],
                    "evaluate_ms": timing.evaluate_ms[system],
                    "build_dispatch_ms": timing.dispatch_ms[system],
                }
                for system in sorted(timing.evaluate_ms)
            },
        },
        "baseline": baseline_data,
        "recommendation": recommendation,
        "delta": {
            "predicted_workflow_duration_ms": int(
                recommendation["predicted_workflow_duration_ms"]
            )
            - int(baseline_data["predicted_workflow_duration_ms"]),
            "total_build_runner_ms": int(recommendation["total_build_runner_ms"])
            - int(baseline_data["total_build_runner_ms"]),
            "job_count": int(recommendation["job_count"])
            - int(baseline_data["job_count"]),
        },
    }


def write_summary(plan: dict[str, object]) -> None:
    baseline = require_mapping(plan["baseline"], "baseline")
    recommendation = require_mapping(plan["recommendation"], "recommendation")
    rollout = require_mapping(plan["rollout"], "rollout")
    lines = [
        "### CI matrix shadow optimization",
        "",
        "| Metric | Baseline | Recommendation |",
        "| --- | ---: | ---: |",
        f"| Predicted workflow | {int(baseline['predicted_workflow_duration_ms']) / 1000:.1f}s | {int(recommendation['predicted_workflow_duration_ms']) / 1000:.1f}s |",
        f"| Build runner time | {int(baseline['total_build_runner_ms']) / 1000:.1f}s | {int(recommendation['total_build_runner_ms']) / 1000:.1f}s |",
        f"| Build jobs | {baseline['job_count']} | {recommendation['job_count']} |",
        "",
        f"Rollout: `shadow`; data ready: `{str(rollout['data_ready']).lower()}`.",
        "",
    ]
    message = "\n".join(lines)
    print(message)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with Path(summary).open("a", encoding="utf-8") as output:
            output.write(message)


def rollout_decision(
    *,
    has_work: bool,
    usable_sample_count: int,
    minimum_history_runs: int,
    coverage_complete: bool,
    stage_statuses: Sequence[str],
) -> tuple[bool, str]:
    performance_optimal = tuple(stage_statuses[:2]) == (
        "optimal",
        "optimal",
    ) and (
        len(stage_statuses) < 3
        or stage_statuses[2] in {"optimal", "feasible", "unknown"}
    )
    if not has_work:
        return False, "no_build_work"
    if usable_sample_count < minimum_history_runs:
        return False, "insufficient_history"
    if not coverage_complete:
        return False, "insufficient_cost_coverage"
    if not performance_optimal:
        return False, "solver_not_proven_optimal"
    return True, "shadow_only"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--target", required=True, type=Path)
    parser.add_argument("--history-root", required=True, type=Path)
    parser.add_argument("--timing", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--schema", required=True, type=Path)
    parser.add_argument("--max-history-runs", type=int, default=10)
    parser.add_argument("--minimum-history-runs", type=int, default=10)
    parser.add_argument("--minimum-dependency-samples", type=int, default=3)
    parser.add_argument("--max-jobs-per-system", type=int, default=8)
    parser.add_argument("--makespan-slack-ms", type=int, default=0)
    parser.add_argument("--solver-time-limit-seconds", type=float, default=5.0)
    parser.add_argument("--robust-quantile", type=float, default=0.75)
    arguments = parser.parse_args()
    if not 1 <= arguments.max_history_runs <= 100:
        raise ValueError("max history runs must be between 1 and 100")
    if not 1 <= arguments.minimum_history_runs <= arguments.max_history_runs:
        raise ValueError("minimum history runs must fit within the history window")
    if not 1 <= arguments.minimum_dependency_samples <= arguments.minimum_history_runs:
        raise ValueError(
            "minimum dependency samples must fit within the history threshold"
        )
    if not 1 <= arguments.max_jobs_per_system <= 32:
        raise ValueError("max jobs per system must be between 1 and 32")
    if not 0 <= arguments.makespan_slack_ms <= 3_600_000:
        raise ValueError("makespan slack must be between 0 and one hour")
    if not 0.1 <= arguments.solver_time_limit_seconds <= 60:
        raise ValueError("solver time limit must be between 0.1 and 60 seconds")
    if not 0.5 <= arguments.robust_quantile <= 1:
        raise ValueError("robust quantile must be between 0.5 and 1")

    target = load_run(arguments.target)
    history = discover_history(
        arguments.history_root, arguments.target, arguments.max_history_runs
    )
    history = compatible_history(history, target)
    if not history:
        raise ValueError("target run has no compatible runner class")
    target_timing = parse_timing(arguments.timing, target)
    timing_samples = [target_timing]
    target_source = require_mapping(target.index["source"], "run source")
    target_identity = (
        str(target_source["run_id"]),
        require_nonnegative_integer(
            target_source.get("run_attempt"), "source run attempt"
        ),
    )
    seen_timing_runs = {target_identity}
    for run in history:
        run_source = require_mapping(run.index["source"], "run source")
        identity = (
            str(run_source["run_id"]),
            require_nonnegative_integer(
                run_source.get("run_attempt"), "source run attempt"
            ),
        )
        timing_path = run.directory / "workflow-timing.json"
        if identity in seen_timing_runs or not timing_path.exists():
            continue
        try:
            timing_samples.append(parse_timing(timing_path, run))
        except (
            KeyError,
            RecursionError,
            UnicodeError,
            json.JSONDecodeError,
            OSError,
            ValueError,
        ):
            continue
        seen_timing_runs.add(identity)
    timing = aggregate_timing(target_timing, timing_samples, arguments.robust_quantile)
    plan = create_plan(
        target=target,
        history=history,
        timing=timing,
        max_jobs_per_system=arguments.max_jobs_per_system,
        makespan_slack_ms=arguments.makespan_slack_ms,
        solver_time_limit_seconds=arguments.solver_time_limit_seconds,
        robust_quantile=arguments.robust_quantile,
        minimum_history_runs=arguments.minimum_history_runs,
        minimum_dependency_samples=arguments.minimum_dependency_samples,
    )
    atomic_write_json(arguments.output, plan)
    schema_output = arguments.output.parent / "schemas" / arguments.schema.name
    schema_output.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(arguments.schema, schema_output)
    write_summary(plan)


if __name__ == "__main__":
    try:
        main()
    except (
        KeyError,
        RecursionError,
        UnicodeError,
        json.JSONDecodeError,
        OSError,
        RuntimeError,
        ValueError,
    ) as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
