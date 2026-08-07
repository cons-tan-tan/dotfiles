#!/usr/bin/env python3

"""Unit tests for conservative Hestia matrix optimization."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).parents[1] / "_scripts"
sys.path.insert(0, str(SCRIPT_DIR))

from optimize_hestia_matrix import optimize_rows


def row(name: str, index: int, *, os: str = "ubuntu-latest") -> dict[str, object]:
    drv = f"/nix/store/{index:032d}-{name}.drv"
    return {
        "attr": f"lib.hestiaJobs.ci.x86_64-linux.{name}",
        "drvPath": drv,
        "installables": f"{drv}^*",
        "name": name,
        "os": [os],
        "system": "x86_64-linux",
    }


class OptimizeRowsTests(unittest.TestCase):
    def without_telemetry(
        self, rows: list[dict[str, object]]
    ) -> list[dict[str, object]]:
        return [
            {
                key: value
                for key, value in row.items()
                if key not in {"jobId", "telemetryKey"}
            }
            for row in rows
        ]

    def optimize(
        self,
        rows: list[dict[str, object]],
        plans: list[frozenset[str]],
    ) -> list[dict[str, object]]:
        return optimize_rows(
            rows,
            plans,
            critical_path_slack=0.05,
            min_shared_derivations=20,
            min_shared_ratio=0.25,
        )

    def test_merges_shared_work_without_extending_estimated_critical_path(self) -> None:
        rows = [row("configurations", 1), row("eval-tests", 2), row("quality", 3)]
        plans = [
            frozenset(f"drv-{index}" for index in range(100)),
            frozenset(f"drv-{index}" for index in range(20))
            | frozenset(f"eval-{index}" for index in range(5)),
            frozenset(f"quality-{index}" for index in range(10)),
        ]

        optimized = self.optimize(rows, plans)

        self.assertEqual(len(optimized), 2)
        self.assertEqual(optimized[0]["name"], "configurations+eval-tests")
        self.assertIn(rows[0]["installables"], optimized[0]["installables"])
        self.assertIn(rows[1]["installables"], optimized[0]["installables"])
        self.assertEqual(optimized[1]["name"], "quality")

    def test_keeps_groups_when_overlap_is_too_small(self) -> None:
        rows = [row("first", 1), row("second", 2)]
        plans = [
            frozenset(f"first-{index}" for index in range(100)),
            frozenset(f"second-{index}" for index in range(100)),
        ]

        self.assertEqual(self.without_telemetry(self.optimize(rows, plans)), rows)

    def test_keeps_groups_when_merge_would_extend_critical_path(self) -> None:
        rows = [row("first", 1), row("second", 2)]
        plans = [
            frozenset(f"shared-{index}" for index in range(20))
            | frozenset(f"first-{index}" for index in range(80)),
            frozenset(f"shared-{index}" for index in range(20))
            | frozenset(f"second-{index}" for index in range(80)),
        ]

        self.assertEqual(self.without_telemetry(self.optimize(rows, plans)), rows)

    def test_keeps_different_runner_requirements_separate(self) -> None:
        rows = [row("ubuntu", 1), row("self-hosted", 2, os="self-hosted")]
        shared = frozenset(f"drv-{index}" for index in range(100))

        optimized = self.without_telemetry(self.optimize(rows, [shared, shared]))
        self.assertEqual(
            sorted(optimized, key=lambda item: str(item["name"])),
            sorted(rows, key=lambda item: str(item["name"])),
        )

    def test_job_identity_is_independent_of_derivation_paths(self) -> None:
        first = self.optimize([row("first", 1)], [frozenset({"one"})])[0]
        changed = row("first", 9)
        second = self.optimize([changed], [frozenset({"two"})])[0]

        self.assertEqual(first["jobId"], second["jobId"])
        self.assertEqual(first["telemetryKey"], second["telemetryKey"])


if __name__ == "__main__":
    unittest.main()
