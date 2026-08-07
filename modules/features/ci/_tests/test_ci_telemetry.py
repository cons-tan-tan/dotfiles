#!/usr/bin/env python3

"""Contract tests for versioned CI telemetry collection."""

from __future__ import annotations

import copy
import shutil
import subprocess
import sys
import tempfile
import unittest
from io import StringIO
from pathlib import Path
from unittest.mock import patch

SCRIPT_DIR = Path(__file__).parents[1] / "_scripts"
sys.path.insert(0, str(SCRIPT_DIR))

from assemble_ci_telemetry import assemble, failed_bundle
from capture_hestia_eval import capture, command
from ci_telemetry import (
    SCHEMA_ID,
    atomic_write_json,
    check_id,
    document,
    job_identity,
    validate_document,
)
from optimize_hestia_matrix import (
    collect_group_plans,
    member_ids_for_rows,
)
from run_hestia_build import run_build
from validate_hestia_matrix import validate_conservation, validate_matrix


def drv(index: int, name: str) -> str:
    return f"/nix/store/{index:032d}-{name}.drv"


def row(name: str, roots: list[str]) -> dict[str, object]:
    return {
        "attr": name,
        "drvPath": roots[0],
        "installables": " ".join(f"{root}^*" for root in roots),
        "name": name,
        "os": ["ubuntu-latest"],
        "system": "x86_64-linux",
    }


class TelemetryTests(unittest.TestCase):
    def test_eval_capture_keeps_the_exact_stream(self) -> None:
        class Process:
            stdout = iter(['{"attr":"quality"}\n'])

            @staticmethod
            def wait() -> int:
                return 0

        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "eval.jsonl"
            with patch("capture_hestia_eval.subprocess.Popen", return_value=Process()):
                with patch("capture_hestia_eval.sys.stdout", new=StringIO()) as output:
                    self.assertEqual(capture(["--flake", ".#checks"], target), 0)
                    self.assertEqual(output.getvalue(), '{"attr":"quality"}\n')
            self.assertEqual(target.read_text(), '{"attr":"quality"}\n')
        self.assertEqual(command([])[0:3], ["nix", "run", "nixpkgs#nix-eval-jobs"])

    def test_eval_capture_rejects_conflicting_derivation_groups(self) -> None:
        class Process:
            stdout = iter(
                [
                    '{"attr":"first","drvPath":"/nix/store/shared.drv",'
                    '"meta":{"hestia":{"group":"linux-first"}}}\n',
                    '{"attr":"second","drvPath":"/nix/store/shared.drv",'
                    '"meta":{"hestia":{"group":"linux-second"}}}\n',
                ]
            )

            @staticmethod
            def wait() -> int:
                return 0

        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "eval.jsonl"
            with patch("capture_hestia_eval.subprocess.Popen", return_value=Process()):
                with patch("capture_hestia_eval.sys.stdout", new=StringIO()):
                    self.assertEqual(capture(["--flake", ".#checks"], target), 1)
            self.assertEqual(len(target.read_text().splitlines()), 2)

    def test_eval_capture_preserves_non_record_lines(self) -> None:
        class Process:
            stdout = iter(["\n", "not-json\n", "[]\n"])

            @staticmethod
            def wait() -> int:
                return 0

        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "eval.jsonl"
            with patch("capture_hestia_eval.subprocess.Popen", return_value=Process()):
                with patch("capture_hestia_eval.sys.stdout", new=StringIO()) as output:
                    self.assertEqual(capture(["--flake", ".#checks"], target), 0)
                    self.assertEqual(output.getvalue(), "\nnot-json\n[]\n")
            self.assertEqual(target.read_text(), "\nnot-json\n[]\n")

    def test_stable_ids_do_not_depend_on_drv_hashes(self) -> None:
        identity = check_id("x86_64-linux", "lib.hestiaJobs.ci.x86_64-linux.quality")
        first = job_identity(
            system="x86_64-linux",
            runner_labels=["ubuntu-latest"],
            member_check_ids=[identity],
        )
        second = job_identity(
            system="x86_64-linux",
            runner_labels=["ubuntu-latest"],
            member_check_ids=[identity],
        )
        self.assertEqual(first, second)
        self.assertEqual(len(first[0]), 64)
        self.assertEqual(len(first[1]), 20)

    def test_plan_uses_one_dry_run_and_intersects_root_closures(self) -> None:
        first, second = drv(1, "first"), drv(2, "second")
        shared, only_first, cached = (
            drv(3, "shared"),
            drv(4, "only-first"),
            drv(5, "cached"),
        )
        plan_calls: list[list[str]] = []

        def plan_provider(rows, _timeout):
            plan_calls.append([str(item["name"]) for item in rows])
            return frozenset({shared, only_first}), 12

        closures = {
            first: frozenset({shared, only_first, cached}),
            second: frozenset({shared, cached}),
        }
        plans, missing, duration, root_plans = collect_group_plans(
            [row("first", [first]), row("second", [second])],
            timeout_seconds=10,
            plan_provider=plan_provider,
            closure_provider=lambda root, _timeout: closures[root],
        )

        self.assertEqual(plan_calls, [["first", "second"]])
        self.assertEqual(plans, [frozenset({shared, only_first}), frozenset({shared})])
        self.assertEqual(missing, frozenset({shared, only_first}))
        self.assertEqual(duration, 12)
        self.assertEqual(root_plans[first], frozenset({shared, only_first}))
        self.assertEqual(root_plans[second], frozenset({shared}))

    def test_raw_manifest_preserves_cached_and_alias_checks(self) -> None:
        root = drv(1, "root")
        cached = drv(2, "cached")
        records = [
            {
                "attr": "first",
                "drvPath": root,
                "system": "x86_64-linux",
                "isCached": False,
            },
            {
                "attr": "alias",
                "drvPath": root,
                "system": "x86_64-linux",
                "isCached": False,
            },
            {
                "attr": "cached",
                "drvPath": cached,
                "system": "x86_64-linux",
                "isCached": True,
            },
        ]
        members, checks, complete = member_ids_for_rows(
            [row("group", [root])], records, "lib.hestiaJobs.ci.x86_64-linux"
        )

        self.assertTrue(complete)
        self.assertEqual(len(members[0]), 2)
        self.assertEqual(
            [item["selection"] for item in checks],
            ["scheduled", "cached_filtered", "scheduled"],
        )

    def test_missing_manifest_members_create_unknown_root_placeholders(self) -> None:
        roots = [drv(1, "first"), drv(2, "second")]
        members, checks, complete = member_ids_for_rows(
            [row("group", roots)], [], "lib.hestiaJobs.ci.x86_64-linux"
        )

        self.assertFalse(complete)
        self.assertEqual(len(members[0]), 2)
        self.assertEqual({item["drv_path"] for item in checks}, set(roots))
        self.assertEqual({item["selection"] for item in checks}, {"unknown"})

    def test_conservation_rejects_missing_and_duplicate_roots(self) -> None:
        first, second = drv(1, "first"), drv(2, "second")
        original = (
            '{"include":['
            + __import__("json").dumps(row("first", [first, second]))
            + "]}"
        )
        missing = (
            '{"include":[' + __import__("json").dumps(row("first", [first])) + "]}"
        )
        duplicate = (
            '{"include":['
            + __import__("json").dumps(row("first", [first, first]))
            + "]}"
        )
        with self.assertRaises(ValueError):
            validate_conservation(original, missing)
        with self.assertRaises(ValueError):
            validate_conservation(original, duplicate)

    def test_conservation_rejects_runner_reassignment(self) -> None:
        root = drv(1, "root")
        original_row = row("root", [root])
        moved_row = row("root", [root])
        moved_row["os"] = ["self-hosted"]
        encode = __import__("json").dumps
        with self.assertRaises(ValueError):
            validate_conservation(
                encode({"include": [original_row]}),
                encode({"include": [moved_row]}),
            )

    def test_matrix_rejects_duplicate_telemetry_keys(self) -> None:
        first = row("first", [drv(1, "first")])
        second = row("second", [drv(2, "second")])
        for item in (first, second):
            item["jobId"] = "a" * 64
            item["telemetryKey"] = "b" * 20
        with self.assertRaises(ValueError):
            validate_matrix(
                __import__("json").dumps({"include": [first, second]}),
                "true",
                "x86_64-linux",
                require_telemetry=True,
            )

    def test_bundle_marks_absent_job_as_missing_not_cancelled(self) -> None:
        identity = "x86_64-linux:lib.hestiaJobs.ci.x86_64-linux.check"
        root = drv(1, "root")
        job_id, key = job_identity(
            system="x86_64-linux",
            runner_labels=["ubuntu-latest"],
            member_check_ids=[identity],
        )
        lane = document(
            "lane",
            "x86_64-linux",
            {
                "collection_status": "complete",
                "source": {
                    "hestia_version": "v3.0.0",
                    "manifest_version": "1",
                    "nix_version": "nix 2.34",
                    "plan_method": "single-dry-run-and-store-requisites-v1",
                    "plan_duration_ms": 1,
                },
                "derivations": [],
                "checks": [
                    {
                        "check_id": identity,
                        "attr_path": "lib.hestiaJobs.ci.x86_64-linux.check",
                        "display_name": "check",
                        "drv_id": "0" * 31 + "1",
                        "drv_path": root,
                        "system": "x86_64-linux",
                        "runner_labels": ["ubuntu-latest"],
                        "static_affinity_group": None,
                        "selection": "scheduled",
                        "plan": {"status": "success", "dependency_drv_ids": []},
                    }
                ],
                "static_groups": [],
                "decision": {
                    "algorithm": "hestia-overlap",
                    "algorithm_version": "1",
                    "status": "unchanged",
                    "reason_code": None,
                    "parameters": {
                        "critical_path_slack": 0.05,
                        "min_shared_derivations": 20,
                        "min_shared_ratio": 0.25,
                    },
                    "input_fingerprint": "0" * 64,
                    "jobs": [
                        {
                            "job_id": job_id,
                            "telemetry_key": key,
                            "name": "check",
                            "system": "x86_64-linux",
                            "runner_labels": ["ubuntu-latest"],
                            "member_check_ids": [identity],
                            "root_drv_ids": ["0" * 31 + "1"],
                            "planned_drv_ids": [],
                        }
                    ],
                },
            },
        )
        bundle = assemble(lane, [])
        self.assertEqual(bundle["data"]["collection_status"], "partial")
        self.assertEqual(bundle["data"]["missing_job_ids"], [job_id])
        self.assertEqual(bundle["data"]["missing_fragments"], [])
        invalid_lane_values = []
        for path, value in (
            (("decision", "status"), "garbage"),
            (("decision", "parameters", "critical_path_slack"), "invalid"),
            (("checks", 0, "selection"), "garbage"),
            (("checks", 0, "check_id"), "wrong"),
        ):
            invalid = copy.deepcopy(lane)
            target = invalid["data"]
            for component in path[:-1]:
                target = target[component]
            target[path[-1]] = value
            invalid_lane_values.append(invalid)
        for invalid in invalid_lane_values:
            with self.assertRaises(ValueError):
                validate_document(invalid, "lane")

    def test_missing_lane_produces_a_failed_bundle(self) -> None:
        bundle = failed_bundle("x86_64-linux")
        self.assertEqual(bundle["data"]["collection_status"], "failed")
        self.assertIsNone(bundle["data"]["lane"])
        self.assertEqual(bundle["data"]["missing_fragments"], ["lane"])

    def test_schema_accepts_produced_job_and_failed_bundle(self) -> None:
        validator = shutil.which("check-jsonschema")
        if validator is None:
            self.skipTest("check-jsonschema is not available")
        job_id, key = job_identity(
            system="x86_64-linux",
            runner_labels=["ubuntu-latest"],
            member_check_ids=["check"],
        )
        job = document(
            "job",
            "x86_64-linux",
            {
                "workflow_job": {
                    "role": "system-build",
                    "runner_name": "GitHub Actions test",
                },
                "job_id": job_id,
                "telemetry_key": key,
                "name": "check",
                "system": "x86_64-linux",
                "runner_labels": ["ubuntu-latest"],
                "root_drv_ids": ["0" * 32],
                "status": "success",
                "phases": {
                    name: {"status": "success", "duration_ms": 1, "exit_code": 0}
                    for name in ("github_job_setup", "prefetch", "nix_build")
                },
                "derivation_events": [],
                "substitution_events": [],
                "measurement_quality": "job_wall_clock",
                "nix_version": "nix 2.34",
                "event_parser_version": "1",
                "event_parse_status": "no_events",
                "total_duration_ms": 3,
            },
        )
        invalid_job = copy.deepcopy(job)
        invalid_job["data"]["phases"]["nix_build"]["duration_ms"] = -1
        with self.assertRaises(ValueError):
            validate_document(invalid_job, "job")
        bundle = failed_bundle("x86_64-linux")
        workflow_job = document(
            "workflow_job",
            "x86_64-linux",
            {"role": "flake-eval", "runner_name": "GitHub Actions flake"},
        )
        schema = Path(__file__).parents[1] / "_schemas" / "telemetry-v1.schema.json"
        with tempfile.TemporaryDirectory() as directory:
            job_path = Path(directory) / "job.json"
            bundle_path = Path(directory) / "bundle.json"
            workflow_job_path = Path(directory) / "workflow-job.json"
            atomic_write_json(job_path, job)
            atomic_write_json(bundle_path, bundle)
            atomic_write_json(workflow_job_path, workflow_job)
            result = subprocess.run(
                [
                    validator,
                    "--schemafile",
                    str(schema),
                    str(job_path),
                    str(bundle_path),
                    str(workflow_job_path),
                ],
                check=False,
                capture_output=True,
                text=True,
            )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_build_parser_records_structured_derivation_duration(self) -> None:
        root = drv(1, "root")

        class Process:
            stderr = StringIO(
                f'@nix {{"action":"start","id":7,"type":105,"fields":["{root}"]}}\n'
                '@nix {"action":"stop","id":7}\n'
            )

            @staticmethod
            def wait() -> int:
                return 0

        with patch("run_hestia_build.subprocess.Popen", return_value=Process()):
            code, duration, events, substitutions = run_build([f"{root}^*"])
        self.assertEqual(code, 0)
        self.assertGreaterEqual(duration, 0)
        self.assertEqual(events[0]["drv_path"], root)
        self.assertEqual(events[0]["outcome"], "completed")
        self.assertEqual(substitutions, [])

    def test_unknown_schema_is_rejected(self) -> None:
        value = {
            "$schema": SCHEMA_ID,
            "schema_version": 2,
            "document_type": "job",
            "producer": {"name": "dotfiles-ci-telemetry", "version": "1"},
            "run": {"system": "x86_64-linux"},
            "observed_at": "now",
            "data": {},
        }
        with self.assertRaises(ValueError):
            validate_document(value)

    def test_boolean_run_attempt_is_rejected(self) -> None:
        bundle = failed_bundle("x86_64-linux")
        bundle["run"]["run_attempt"] = True
        with self.assertRaises(ValueError):
            validate_document(bundle, "bundle")


if __name__ == "__main__":
    unittest.main()
