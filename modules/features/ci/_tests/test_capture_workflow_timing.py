from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).parents[1] / "_scripts"
sys.path.insert(0, str(SCRIPT_DIR))

from capture_workflow_timing import load_workflow_identities, normalize  # noqa: E402
from ci_telemetry import atomic_write_json, document  # noqa: E402


class WorkflowTimingTests(unittest.TestCase):
    def fixture(self) -> dict[str, object]:
        return {
            "name": "CI",
            "attempt": 2,
            "conclusion": "success",
            "headSha": "a" * 40,
            "startedAt": "2026-08-06T00:00:00Z",
            "updatedAt": "2026-08-06T00:01:00Z",
            "jobs": [
                {
                    "name": "required",
                    "runnerName": "GitHub Actions 1",
                    "startedAt": "2026-08-06T00:00:50Z",
                    "completedAt": "2026-08-06T00:01:00Z",
                    "conclusion": "success",
                }
            ],
        }

    def test_normalizes_only_stable_timing_fields(self) -> None:
        value = normalize(
            self.fixture(), repository="owner/repo", run_id="123", run_attempt=2
        )

        self.assertEqual(value["repository"], "owner/repo")
        self.assertEqual(value["run_id"], "123")
        self.assertEqual(value["run_attempt"], 2)
        self.assertEqual(value["commit_sha"], "a" * 40)
        self.assertEqual(value["jobs"][0]["name"], "required")

    def test_joins_structured_identity_by_runner_instead_of_display_name(self) -> None:
        raw = self.fixture()
        raw["jobs"][0]["name"] = "freely renamed display label"
        raw["jobs"].append(
            {
                "name": "system / x86_64-linux / build",
                "runnerName": None,
                "startedAt": None,
                "completedAt": None,
                "conclusion": "skipped",
            }
        )
        value = normalize(
            raw,
            repository="owner/repo",
            run_id="123",
            run_attempt=2,
            identities=[
                {
                    "role": "flake-eval",
                    "system": "x86_64-linux",
                    "telemetry_key": None,
                    "runner_name": "GitHub Actions 1",
                }
            ],
        )

        self.assertEqual(value["schema_version"], 2)
        self.assertNotIn("name", value["jobs"][0])
        self.assertEqual(value["jobs"][0]["role"], "flake-eval")
        self.assertEqual(value["jobs"][0]["system"], "x86_64-linux")

    def test_rejects_non_skipped_job_without_runner(self) -> None:
        raw = self.fixture()
        raw["jobs"][0]["runnerName"] = None

        with self.assertRaisesRegex(ValueError, "job runner name"):
            normalize(
                raw,
                repository="owner/repo",
                run_id="123",
                run_attempt=2,
                identities=[
                    {
                        "role": "flake-eval",
                        "system": "x86_64-linux",
                        "telemetry_key": None,
                        "runner_name": "GitHub Actions 1",
                    }
                ],
            )

    def test_rejects_duplicate_job_names(self) -> None:
        value = self.fixture()
        value["jobs"] = [value["jobs"][0], value["jobs"][0]]

        with self.assertRaisesRegex(ValueError, "duplicate"):
            normalize(value, repository="owner/repo", run_id="123", run_attempt=2)

    def test_rejects_another_run_attempt(self) -> None:
        with self.assertRaisesRegex(ValueError, "another attempt"):
            normalize(
                self.fixture(),
                repository="owner/repo",
                run_id="123",
                run_attempt=1,
            )

    def test_loads_flake_and_lane_identities_from_run_telemetry(self) -> None:
        run = {
            "repository": "owner/repo",
            "repository_id": "1",
            "run_id": "123",
            "run_attempt": 2,
            "workflow": "CI",
            "event": "push",
            "ref": "refs/heads/main",
            "commit_sha": "a" * 40,
            "system": "x86_64-linux",
        }
        lane = document(
            "lane",
            "x86_64-linux",
            {
                "workflow_job": {
                    "role": "system-evaluate",
                    "runner_name": "runner-evaluate",
                },
                "collection_status": "complete",
                "source": {
                    "hestia_version": "v3.0.0",
                    "manifest_version": "1",
                    "nix_version": "nix 2.34",
                    "plan_method": "single-dry-run-and-store-requisites-v1",
                    "plan_duration_ms": 0,
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
            run=run,
        )
        bundle = document(
            "bundle",
            "x86_64-linux",
            {
                "collection_status": "complete",
                "lane": lane,
                "jobs": [],
                "missing_job_ids": [],
                "missing_fragments": [],
            },
            run=run,
        )
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            atomic_write_json(root / "systems/x86_64-linux.json", bundle)
            atomic_write_json(
                root / "index.json",
                {
                    "source": {
                        "repository": "owner/repo",
                        "run_id": "123",
                        "run_attempt": 2,
                        "head_sha": "a" * 40,
                    },
                    "workflow_jobs": [
                        {
                            "role": "flake-eval",
                            "system": "x86_64-linux",
                            "runner_name": "runner-flake",
                        }
                    ],
                    "systems": [{"bundle_path": "systems/x86_64-linux.json"}],
                },
            )
            identities = load_workflow_identities(
                root,
                repository="owner/repo",
                run_id="123",
                run_attempt=2,
                commit_sha="a" * 40,
            )

        self.assertEqual(
            {(item["role"], item["runner_name"]) for item in identities},
            {
                ("flake-eval", "runner-flake"),
                ("system-evaluate", "runner-evaluate"),
            },
        )


if __name__ == "__main__":
    unittest.main()
