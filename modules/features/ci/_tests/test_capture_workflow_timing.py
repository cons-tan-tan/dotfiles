from __future__ import annotations

import sys
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).parents[1] / "_scripts"
sys.path.insert(0, str(SCRIPT_DIR))

from capture_workflow_timing import normalize  # noqa: E402


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


if __name__ == "__main__":
    unittest.main()
