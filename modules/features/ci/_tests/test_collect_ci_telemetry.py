#!/usr/bin/env python3

"""Contract tests for the completed-workflow telemetry collector."""

from __future__ import annotations

import copy
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SCRIPT_DIR = Path(__file__).parents[1] / "_scripts"
SCHEMA_DIR = Path(__file__).parents[1] / "_schemas"
sys.path.insert(0, str(SCRIPT_DIR))

from ci_telemetry import atomic_write_json, document
from collect_ci_telemetry import (
    collect,
    expected_run,
    source_from_event,
    validate_run_index,
)

SYSTEMS = ["aarch64-darwin", "x86_64-linux"]


def source_event(conclusion: str = "success") -> dict[str, object]:
    repository = {
        "id": 123,
        "full_name": "cons-tan-tan/dotfiles",
        "default_branch": "main",
    }
    return {
        "action": "completed",
        "repository": repository,
        "workflow_run": {
            "id": 456,
            "run_attempt": 2,
            "workflow_id": 789,
            "name": "CI",
            "path": ".github/workflows/ci.yaml@main",
            "event": "push",
            "status": "completed",
            "conclusion": conclusion,
            "head_sha": "a" * 40,
            "head_branch": "main",
            "created_at": "2026-08-05T00:00:00Z",
            "run_started_at": "2026-08-05T00:01:00Z",
            "updated_at": "2026-08-05T00:02:00Z",
            "repository": repository,
        },
    }


def source_index(event: dict[str, object]) -> dict[str, object]:
    workflow_run = event["workflow_run"]
    assert isinstance(workflow_run, dict)
    return {
        "repository": "cons-tan-tan/dotfiles",
        "repository_id": "123",
        "workflow_id": "789",
        "workflow_name": "CI",
        "workflow_path": ".github/workflows/ci.yaml",
        "run_id": "456",
        "run_attempt": 2,
        "event": "push",
        "head_sha": "a" * 40,
        "head_branch": "main",
        "conclusion": workflow_run["conclusion"],
        "created_at": "2026-08-05T00:00:00Z",
        "run_started_at": "2026-08-05T00:01:00Z",
        "updated_at": "2026-08-05T00:02:00Z",
        "trust_tier": "trusted_default_branch",
    }


def lane(source: dict[str, object], system: str) -> dict[str, object]:
    return document(
        "lane",
        system,
        {
            "collection_status": "complete",
            "source": {
                "hestia_version": "v3.0.0",
                "manifest_version": "manifest",
                "nix_version": "nix 2.34",
                "plan_method": "single-dry-run-and-store-requisites-v1",
                "plan_duration_ms": 1,
            },
            "derivations": [],
            "checks": [],
            "static_groups": [],
            "decision": {
                "algorithm": "hestia-overlap",
                "algorithm_version": "1",
                "status": "not_needed",
                "reason_code": None,
                "parameters": {
                    "critical_path_slack": 0.05,
                    "min_shared_derivations": 20,
                    "min_shared_ratio": 0.25,
                },
                "input_fingerprint": "0" * 64,
                "jobs": [],
            },
        },
        run=expected_run(source, system),
    )


class CollectorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.event_path = self.root / "event.json"
        self.fragments = self.root / "fragments"
        self.workflow_jobs = self.root / "workflow-jobs"
        self.output = self.root / "output"
        self.schema = SCHEMA_DIR / "telemetry-v1.schema.json"
        self.index_schema = SCHEMA_DIR / "telemetry-run-index-v1.schema.json"
        self.collector_environment = {
            "GITHUB_RUN_ID": "900",
            "GITHUB_RUN_ATTEMPT": "3",
            "GITHUB_SHA": "b" * 40,
        }

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def write_event(self, event: dict[str, object]) -> dict[str, object]:
        self.event_path.write_text(json.dumps(event))
        return source_index(event)

    def write_lane(
        self, source: dict[str, object], system: str, *, value=None, attempt: int = 2
    ) -> Path:
        artifact = self.fragments / f"ci-telemetry-fragment-456-{attempt}-{system}-lane"
        artifact.mkdir(parents=True)
        target = artifact / f"lane-{system}.json"
        atomic_write_json(target, lane(source, system) if value is None else value)
        return target

    def write_workflow_job(
        self, source: dict[str, object], system: str, runner_name: str
    ) -> None:
        artifact = self.workflow_jobs / f"ci-workflow-job-456-2-flake-eval-{system}"
        artifact.mkdir(parents=True)
        atomic_write_json(
            artifact / f"workflow-job-{system}.json",
            document(
                "workflow_job",
                system,
                {"role": "flake-eval", "runner_name": runner_name},
                run=expected_run(source, system),
            ),
        )

    def run_collect(self, event: dict[str, object]) -> dict[str, object]:
        self.write_event(event)
        with patch.dict(os.environ, self.collector_environment, clear=False):
            return collect(
                event=self.event_path,
                fragment_root=self.fragments,
                output=self.output,
                schema=self.schema,
                index_schema=self.index_schema,
                systems=SYSTEMS,
            )

    def test_complete_collection_preserves_source_identity_and_hashes(self) -> None:
        event = source_event()
        source = self.write_event(event)
        for system in SYSTEMS:
            self.write_lane(source, system)
        with patch.dict(os.environ, self.collector_environment, clear=False):
            index = collect(
                event=self.event_path,
                fragment_root=self.fragments,
                output=self.output,
                schema=self.schema,
                index_schema=self.index_schema,
                systems=SYSTEMS,
            )

        self.assertEqual(index["collection_status"], "complete")
        self.assertEqual(index["source"]["run_id"], "456")
        self.assertEqual(index["collector"]["run_id"], "900")
        for entry in index["systems"]:
            self.assertEqual(entry["artifact_status"], "available")
            path = self.output / entry["bundle_path"]
            self.assertEqual(
                entry["bundle_sha256"], hashlib.sha256(path.read_bytes()).hexdigest()
            )
            bundle = json.loads(path.read_text())
            self.assertEqual(bundle["run"]["run_id"], "456")
        self.assertTrue((self.output / "schemas" / self.schema.name).is_file())
        self.assertTrue((self.output / "schemas" / self.index_schema.name).is_file())

    def test_collects_structured_flake_job_identities(self) -> None:
        event = source_event()
        source = self.write_event(event)
        for system in SYSTEMS:
            self.write_lane(source, system)
        flake_systems = ["aarch64-darwin", "aarch64-linux", "x86_64-linux"]
        for index, system in enumerate(flake_systems):
            self.write_workflow_job(source, system, f"GitHub Actions {index}")
        with patch.dict(os.environ, self.collector_environment, clear=False):
            result = collect(
                event=self.event_path,
                fragment_root=self.fragments,
                output=self.output,
                schema=self.schema,
                index_schema=self.index_schema,
                systems=SYSTEMS,
                workflow_job_root=self.workflow_jobs,
                workflow_job_systems=flake_systems,
            )

        self.assertEqual(
            [item["system"] for item in result["workflow_jobs"]], flake_systems
        )
        self.assertEqual(
            {item["role"] for item in result["workflow_jobs"]}, {"flake-eval"}
        )

    def test_source_path_accepts_normalized_and_default_branch_suffixes(self) -> None:
        event = source_event()
        self.write_event(event)
        self.assertEqual(
            source_from_event(self.event_path)["workflow_path"],
            ".github/workflows/ci.yaml",
        )
        event["workflow_run"]["path"] = ".github/workflows/ci.yaml"
        self.write_event(event)
        self.assertEqual(
            source_from_event(self.event_path)["workflow_path"],
            ".github/workflows/ci.yaml",
        )
        event["workflow_run"]["path"] = ".github/workflows/ci.yaml@other"
        self.write_event(event)
        with self.assertRaises(ValueError):
            source_from_event(self.event_path)

    def test_one_missing_lane_is_partial_and_all_missing_is_failed(self) -> None:
        event = source_event()
        source = self.write_event(event)
        self.write_lane(source, "x86_64-linux")
        partial = self.run_collect(event)
        self.assertEqual(partial["collection_status"], "partial")
        missing = [
            item for item in partial["systems"] if item["artifact_status"] == "missing"
        ]
        self.assertEqual(missing[0]["reason_code"], "lane_missing")

        with tempfile.TemporaryDirectory() as directory:
            self.fragments = Path(directory) / "absent"
            self.output = Path(directory) / "output"
            failed = self.run_collect(source_event("cancelled"))
        self.assertEqual(failed["collection_status"], "failed")
        self.assertEqual(failed["source"]["conclusion"], "cancelled")
        self.assertEqual(
            {item["execution_conclusion"] for item in failed["systems"]}, {"unknown"}
        )

    def test_source_identity_mismatch_marks_only_that_system_invalid(self) -> None:
        event = source_event()
        source = self.write_event(event)
        invalid = lane(source, "x86_64-linux")
        invalid["run"]["run_attempt"] = 1
        self.write_lane(source, "x86_64-linux", value=invalid)
        self.write_lane(source, "aarch64-darwin")
        index = self.run_collect(event)
        by_system = {item["system"]: item for item in index["systems"]}
        self.assertEqual(by_system["x86_64-linux"]["artifact_status"], "invalid")
        self.assertEqual(by_system["aarch64-darwin"]["artifact_status"], "available")
        self.assertEqual(index["collection_status"], "partial")

    def test_attempt_mixing_and_symlinks_invalidate_the_inventory(self) -> None:
        event = source_event()
        source = self.write_event(event)
        self.write_lane(source, "x86_64-linux", attempt=1)
        index = self.run_collect(event)
        self.assertEqual(index["collection_status"], "failed")
        self.assertEqual(
            {item["reason_code"] for item in index["systems"]},
            {"artifact_inventory_invalid"},
        )

        shutil.rmtree(self.fragments)
        self.output = self.root / "symlink-output"
        artifact = self.fragments / "ci-telemetry-fragment-456-2-x86_64-linux-lane"
        artifact.mkdir(parents=True)
        (artifact / "lane-x86_64-linux.json").symlink_to(self.event_path)
        index = self.run_collect(event)
        self.assertEqual(index["collection_status"], "failed")
        self.assertEqual(index["systems"][0]["artifact_status"], "invalid")

    def test_download_failure_and_deep_json_still_produce_an_index(self) -> None:
        event = source_event("cancelled")
        self.write_event(event)
        with patch.dict(os.environ, self.collector_environment, clear=False):
            failed = collect(
                event=self.event_path,
                fragment_root=self.fragments,
                output=self.output,
                schema=self.schema,
                index_schema=self.index_schema,
                systems=SYSTEMS,
                download_outcome="failed",
            )
        self.assertEqual(failed["artifact_download_status"], "failed")
        self.assertEqual(
            {item["reason_code"] for item in failed["systems"]},
            {"artifact_download_failed"},
        )

        self.output = self.root / "deep-output"
        artifact = self.fragments / "ci-telemetry-fragment-456-2-x86_64-linux-lane"
        artifact.mkdir(parents=True)
        (artifact / "lane-x86_64-linux.json").write_text("[" * 1100 + "]" * 1100)
        deep = self.run_collect(event)
        by_system = {item["system"]: item for item in deep["systems"]}
        self.assertEqual(by_system["x86_64-linux"]["artifact_status"], "invalid")

    def test_run_index_semantic_mutations_are_rejected(self) -> None:
        event = source_event()
        source = self.write_event(event)
        for system in SYSTEMS:
            self.write_lane(source, system)
        index = self.run_collect(event)
        mutations = []

        wrong_status = copy.deepcopy(index)
        wrong_status["collection_status"] = "partial"
        mutations.append(wrong_status)

        duplicate_system = copy.deepcopy(index)
        duplicate_system["systems"][1]["system"] = duplicate_system["systems"][0][
            "system"
        ]
        mutations.append(duplicate_system)

        missing_hash = copy.deepcopy(index)
        missing_hash["systems"][0]["bundle_sha256"] = None
        mutations.append(missing_hash)

        missing_with_path = copy.deepcopy(index)
        missing_with_path["systems"][0]["artifact_status"] = "missing"
        missing_with_path["systems"][0]["reason_code"] = "lane_missing"
        mutations.append(missing_with_path)

        for mutation in mutations:
            with self.assertRaises(ValueError):
                validate_run_index(mutation)

    def test_output_documents_match_both_json_schemas(self) -> None:
        validator = shutil.which("check-jsonschema")
        if validator is None:
            self.skipTest("check-jsonschema is not available")
        event = source_event()
        source = self.write_event(event)
        for system in SYSTEMS:
            self.write_lane(source, system)
        self.run_collect(event)
        index_result = subprocess.run(
            [
                validator,
                "--schemafile",
                str(self.index_schema),
                str(self.output / "index.json"),
            ],
            check=False,
            capture_output=True,
            text=True,
        )
        bundle_result = subprocess.run(
            [
                validator,
                "--schemafile",
                str(self.schema),
                *[
                    str(self.output / "systems" / f"{system}.json")
                    for system in SYSTEMS
                ],
            ],
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(
            index_result.returncode, 0, index_result.stdout + index_result.stderr
        )
        self.assertEqual(
            bundle_result.returncode, 0, bundle_result.stdout + bundle_result.stderr
        )


if __name__ == "__main__":
    unittest.main()
