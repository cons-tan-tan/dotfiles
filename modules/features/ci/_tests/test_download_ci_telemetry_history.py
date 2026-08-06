from __future__ import annotations

import hashlib
import json
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest import mock

SCRIPT_DIR = Path(__file__).parents[1] / "_scripts"
sys.path.insert(0, str(SCRIPT_DIR))

from ci_telemetry import atomic_write_json, document  # noqa: E402
from download_ci_telemetry_history import (  # noqa: E402
    INDEX_SCHEMA_ID,
    list_artifacts,
    safe_extract,
    trusted_collector_run,
    valid_artifact_inventory,
    valid_run,
)


class TelemetryHistoryTests(unittest.TestCase):
    def write_complete_artifact(self, root: Path) -> tuple[dict[str, object], Path]:
        source = {
            "repository": "owner/repo",
            "repository_id": "1",
            "workflow_id": "2",
            "workflow_name": "CI",
            "workflow_path": ".github/workflows/ci.yaml",
            "run_id": "123",
            "run_attempt": 1,
            "event": "push",
            "head_sha": "a" * 40,
            "head_branch": "main",
            "conclusion": "success",
            "created_at": "2026-08-06T00:00:00Z",
            "run_started_at": "2026-08-06T00:00:00Z",
            "updated_at": "2026-08-06T00:01:00Z",
            "trust_tier": "trusted_default_branch",
        }
        run = {
            "repository": "owner/repo",
            "repository_id": "1",
            "run_id": "123",
            "run_attempt": 1,
            "workflow": "CI",
            "event": "push",
            "ref": "refs/heads/main",
            "commit_sha": "a" * 40,
            "system": "x86_64-linux",
        }
        bundle = document(
            "bundle",
            "x86_64-linux",
            {
                "collection_status": "complete",
                "lane": None,
                "jobs": [],
                "missing_job_ids": [],
                "missing_fragments": ["lane"],
            },
            run=run,
        )
        bundle_path = root / "systems" / "x86_64-linux.json"
        atomic_write_json(bundle_path, bundle)
        schema_root = root / "schemas"
        schema_root.mkdir()
        (schema_root / "telemetry-v1.schema.json").write_text("{}\n")
        (schema_root / "telemetry-run-index-v1.schema.json").write_text("{}\n")
        index = {
            "$schema": INDEX_SCHEMA_ID,
            "schema_version": 1,
            "document_type": "run_index",
            "producer": {"name": "dotfiles-ci-telemetry", "version": "1.0.0"},
            "observed_at": "2026-08-06T00:01:00Z",
            "source": source,
            "collector": {
                "run_id": "20",
                "run_attempt": 2,
                "commit_sha": "b" * 40,
            },
            "artifact_download_status": "success",
            "collection_status": "complete",
            "expected_systems": ["x86_64-linux"],
            "systems": [
                {
                    "system": "x86_64-linux",
                    "artifact_status": "available",
                    "reason_code": None,
                    "bundle_path": "systems/x86_64-linux.json",
                    "bundle_sha256": hashlib.sha256(
                        bundle_path.read_bytes()
                    ).hexdigest(),
                    "bundle_collection_status": "complete",
                    "execution_conclusion": "success",
                }
            ],
        }
        atomic_write_json(root / "index.json", index)
        return index, bundle_path

    def test_selects_only_bounded_unexpired_telemetry_artifacts(self) -> None:
        response = {
            "artifacts": [
                {
                    "id": 1,
                    "name": "ci-telemetry-run-v1-source-10-1-collector-20-1",
                    "size_in_bytes": 1024,
                    "expired": False,
                    "created_at": "2026-08-06T00:00:00Z",
                    "workflow_run": {"id": 20},
                },
                {
                    "id": 2,
                    "name": "unrelated",
                    "size_in_bytes": 1024,
                    "expired": False,
                    "created_at": "2026-08-06T00:01:00Z",
                    "workflow_run": {"id": 21},
                },
                {
                    "id": 3,
                    "name": "ci-telemetry-run-v1-source-30-1-collector-40-1",
                    "size_in_bytes": 1024,
                    "expired": True,
                    "created_at": "2026-08-06T00:02:00Z",
                    "workflow_run": {"id": 40},
                },
            ]
        }
        with mock.patch("download_ci_telemetry_history.gh_json", return_value=response):
            selected = list_artifacts("owner/repo")

        self.assertEqual([item["id"] for item in selected], [1])

    def test_safe_extract_rejects_parent_traversal(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive = root / "artifact.zip"
            with zipfile.ZipFile(archive, "w") as output:
                output.writestr("../outside", "unsafe")

            with self.assertRaisesRegex(ValueError, "unsafe"):
                safe_extract(archive, root / "output")

    def test_validates_inventory_digest_and_bundle_identity(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            index, bundle_path = self.write_complete_artifact(root)

            self.assertTrue(valid_artifact_inventory(root, index))
            bundle_path.write_text("{}\n")
            self.assertFalse(valid_artifact_inventory(root, index))

    def test_trusts_only_the_default_branch_collector_workflow(self) -> None:
        response = {
            "name": "CI telemetry",
            "path": ".github/workflows/ci-telemetry.yaml",
            "event": "workflow_run",
            "head_branch": "main",
            "head_sha": "b" * 40,
            "run_attempt": 2,
            "status": "completed",
            "conclusion": "success",
            "repository": {"full_name": "owner/repo"},
        }
        with mock.patch(
            "download_ci_telemetry_history.gh_json", return_value=response
        ) as api:
            self.assertEqual(trusted_collector_run("owner/repo", "20", 2), "b" * 40)
            self.assertIn("/attempts/2", api.call_args.args[0][0])

        with mock.patch("download_ci_telemetry_history.gh_json", return_value=response):
            self.assertIsNone(trusted_collector_run("owner/repo", "20", 1))

        response["event"] = "pull_request"
        with mock.patch("download_ci_telemetry_history.gh_json", return_value=response):
            self.assertIsNone(trusted_collector_run("owner/repo", "20", 2))

    def test_valid_run_requires_trusted_successful_collection(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            index, _bundle_path = self.write_complete_artifact(root)

            self.assertEqual(valid_run(root, "owner/repo"), ("123", 1))
            self.assertIsNone(valid_run(root, "other/repo"))
            del index["source"]["repository_id"]
            atomic_write_json(root / "index.json", index)
            self.assertIsNone(valid_run(root, "owner/repo"))


if __name__ == "__main__":
    unittest.main()
