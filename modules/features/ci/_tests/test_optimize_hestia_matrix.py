#!/usr/bin/env python3

"""Behavioral tests for lightweight Hestia grouping and bounded plan collection."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from io import StringIO
from pathlib import Path
from unittest.mock import Mock, patch

SCRIPT_DIR = Path(__file__).parents[1] / "_scripts"
sys.path.insert(0, str(SCRIPT_DIR))

from optimize_hestia_matrix import (
    collect_group_plans,
    collect_missing_plan,
    main,
    optimize_rows,
    query_requisites,
)
from validate_hestia_matrix import validate_conservation


def drv(index: int, name: str) -> str:
    return f"/nix/store/{index:032d}-{name}.drv"


def row(
    name: str,
    index: int,
    *,
    os: str = "ubuntu-latest",
    extra_roots: tuple[str, ...] = (),
) -> dict[str, object]:
    root = drv(index, name)
    return {
        "attr": f"lib.hestiaJobs.ci.x86_64-linux.{name}",
        "drvPath": root,
        "installables": " ".join(path + "^*" for path in (root, *extra_roots)),
        "name": name,
        "os": [os],
        "system": "x86_64-linux",
    }


class OptimizeRowsTests(unittest.TestCase):
    def optimize(self, rows, plans, *, minimum=1):
        result = optimize_rows(
            rows,
            plans,
            critical_path_slack=0.05,
            min_shared_derivations=minimum,
            min_shared_ratio=0.25,
        )
        validate_conservation(
            json.dumps({"include": rows}), json.dumps({"include": result})
        )
        return result

    def test_merges_shared_work_within_the_derivation_count_limit(self):
        rows = [row("configurations", 1), row("eval-tests", 2), row("quality", 3)]
        plans = [
            frozenset(f"drv-{index}" for index in range(100)),
            frozenset(f"drv-{index}" for index in range(20))
            | frozenset(f"eval-{index}" for index in range(5)),
            frozenset(f"quality-{index}" for index in range(10)),
        ]
        optimized = self.optimize(rows, plans)
        self.assertEqual(
            [item["name"] for item in optimized],
            ["configurations+eval-tests", "quality"],
        )

    def test_small_groups_can_share_fewer_than_twenty_derivations(self):
        rows = [row("configurations", 1), row("package-smoke", 2)]
        plans = [
            frozenset(f"shared-{i}" for i in range(100)),
            frozenset(f"shared-{i}" for i in range(4)) | frozenset({"smoke-test"}),
        ]
        self.assertEqual(len(self.optimize(rows, plans)), 1)
        self.assertEqual(len(self.optimize(rows, plans, minimum=20)), 2)

    def test_keeps_independent_groups_and_preserves_empty_plans(self):
        rows = [row("first", 1), row("second", 2)]
        for plans in ([frozenset({"a"}), frozenset({"b"})], [frozenset(), frozenset()]):
            with self.subTest(plans=plans):
                self.assertEqual(self.optimize(rows, plans), rows)

    def test_keeps_groups_when_merge_exceeds_the_count_limit(self):
        rows = [row("first", 1), row("second", 2)]
        shared = frozenset(f"shared-{i}" for i in range(20))
        plans = [
            shared | frozenset(f"first-{i}" for i in range(80)),
            shared | frozenset(f"second-{i}" for i in range(80)),
        ]
        self.assertEqual(self.optimize(rows, plans), rows)

    def test_keeps_groups_with_a_small_shared_ratio(self):
        rows = [row("first", 1), row("second", 2), row("large", 3)]
        plans = [
            frozenset({"shared", "a", "b", "c", "d"}),
            frozenset({"shared", "e", "f", "g", "h"}),
            frozenset(f"large-{i}" for i in range(100)),
        ]
        self.assertEqual(len(self.optimize(rows, plans)), 3)

    def test_keeps_different_runner_and_system_requirements_separate(self):
        first = row("first", 1)
        for change in ({"os": ["self-hosted"]}, {"system": "aarch64-darwin"}):
            second = row("second", 2) | change
            with self.subTest(change=change):
                self.assertEqual(
                    len(self.optimize([first, second], [frozenset({"shared"})] * 2)), 2
                )

    def test_grouping_is_deterministic_and_preserves_every_installable(self):
        rows = [
            row("first", 1, extra_roots=(drv(4, "alias"),)),
            row("second", 2),
            row("third", 3),
        ]
        plans = [frozenset({"shared"})] * 3
        self.assertEqual(
            self.optimize(rows, plans),
            self.optimize(list(reversed(rows)), list(reversed(plans))),
        )


class PlanCollectionTests(unittest.TestCase):
    def test_one_dry_run_and_one_multi_root_query_per_group(self):
        first, second, third = drv(1, "first"), drv(2, "second"), drv(3, "third")
        shared, unique, cached = drv(4, "shared"), drv(5, "unique"), drv(6, "cached")
        rows = [row("first", 1, extra_roots=(second,)), row("third", 3)]
        plan = Mock(return_value=frozenset({shared, unique}))
        query = Mock(
            side_effect=[
                frozenset({shared, unique, cached}),
                frozenset({shared, cached}),
            ]
        )
        result = collect_group_plans(
            rows,
            timeout_seconds=30,
            min_shared_derivations=1,
            plan_provider=plan,
            closure_provider=query,
        )
        self.assertEqual(result, [frozenset({shared, unique}), frozenset({shared})])
        self.assertEqual(plan.call_count, 1)
        self.assertEqual(
            [call.args[0] for call in query.call_args_list],
            [sorted([first, second]), [third]],
        )

    def test_skips_all_nix_calls_without_a_compatible_pair(self):
        for rows in (
            [],
            [row("only", 1)],
            [row("first", 1), row("second", 2, os="self-hosted")],
        ):
            with self.subTest(rows=rows):
                plan, query = Mock(), Mock()
                self.assertIsNone(
                    collect_group_plans(
                        rows,
                        timeout_seconds=30,
                        min_shared_derivations=1,
                        plan_provider=plan,
                        closure_provider=query,
                    )
                )
                plan.assert_not_called()
                query.assert_not_called()

    def test_skips_closures_below_the_configured_shared_threshold(self):
        rows = [row("first", 1), row("second", 2)]
        for count, minimum, expected_calls in ((0, 1, 0), (19, 20, 0), (20, 20, 2)):
            with self.subTest(count=count, minimum=minimum):
                query = Mock(return_value=frozenset())
                result = collect_group_plans(
                    rows,
                    timeout_seconds=30,
                    min_shared_derivations=minimum,
                    plan_provider=lambda *_: frozenset(
                        f"drv-{i}" for i in range(count)
                    ),
                    closure_provider=query,
                )
                self.assertEqual(query.call_count, expected_calls)
                if not expected_calls:
                    self.assertIsNone(result)

    def test_dry_run_and_closures_share_one_deadline(self):
        clock = Mock(return_value=0.0)
        calls = []

        def plan(_rows, timeout):
            calls.append(timeout)
            clock.return_value = 4.0
            return frozenset({"shared"})

        def query(_roots, timeout):
            calls.append(timeout)
            clock.return_value += 2.0
            return frozenset({"shared"})

        with patch("optimize_hestia_matrix.time.monotonic", clock):
            collect_group_plans(
                [row("first", 1), row("second", 2)],
                timeout_seconds=10,
                min_shared_derivations=1,
                plan_provider=plan,
                closure_provider=query,
            )
        self.assertEqual(calls, [10.0, 6.0, 4.0])

    def test_stops_after_the_first_failed_query(self):
        rows = [row("first", 1), row("second", 2), row("third", 3)]
        for failure_index in (0, 1):
            query = Mock(
                side_effect=[frozenset({"shared"})] * failure_index
                + [RuntimeError("query failed")]
            )
            with self.subTest(failure_index=failure_index):
                with self.assertRaisesRegex(RuntimeError, "query failed"):
                    collect_group_plans(
                        rows,
                        timeout_seconds=30,
                        min_shared_derivations=1,
                        plan_provider=lambda *_: frozenset({"shared"}),
                        closure_provider=query,
                    )
                self.assertEqual(query.call_count, failure_index + 1)

    def test_stops_before_the_next_query_when_the_deadline_expires(self):
        for expired_phase in ("dry-run", "closure"):
            clock = Mock(return_value=0.0)

            def plan(*_args):
                if expired_phase == "dry-run":
                    clock.return_value = 10.0
                return frozenset({"shared"})

            def query(*_args):
                clock.return_value = 10.0
                return frozenset({"shared"})

            closure = Mock(side_effect=query)
            with self.subTest(expired_phase=expired_phase):
                with patch("optimize_hestia_matrix.time.monotonic", clock):
                    with self.assertRaises(subprocess.TimeoutExpired):
                        collect_group_plans(
                            [row("first", 1), row("second", 2)],
                            timeout_seconds=10,
                            min_shared_derivations=1,
                            plan_provider=plan,
                            closure_provider=closure,
                        )
                self.assertEqual(
                    closure.call_count, 0 if expired_phase == "dry-run" else 1
                )

    def test_forwards_deadline_timeouts_to_both_subprocesses(self):
        roots = [drv(1, "first"), drv(2, "second")]
        result = subprocess.CompletedProcess(
            [],
            0,
            stdout="\n".join(roots + ["/nix/store/source"]),
            stderr=f"  {roots[0]}\n",
        )
        with patch("optimize_hestia_matrix.subprocess.run", return_value=result) as run:
            missing = collect_missing_plan([row("first", 1)], 1.5)
            self.assertEqual(missing, frozenset({roots[0]}))
            self.assertEqual(run.call_args.kwargs["timeout"], 1.5)
            self.assertEqual(run.call_args.kwargs["env"]["LC_ALL"], "C")
            closure = query_requisites(roots, 0.5)
            self.assertEqual(closure, frozenset(roots))
            self.assertEqual(
                run.call_args.args[0], ["nix-store", "--query", "--requisites", *roots]
            )
            self.assertEqual(run.call_args.kwargs["timeout"], 0.5)


class MatrixBoundaryTests(unittest.TestCase):
    def test_conservation_rejects_missing_duplicate_and_reassigned_work(self):
        original = {"include": [row("first", 1), row("second", 2)]}
        alternatives = [
            {"include": [row("first", 1)]},
            {"include": [row("first", 1), row("first", 1)]},
            {"include": [row("first", 1), row("second", 2, os="self-hosted")]},
        ]
        for alternative in alternatives:
            with self.subTest(alternative=alternative):
                with self.assertRaises(ValueError):
                    validate_conservation(json.dumps(original), json.dumps(alternative))

    def test_all_plan_failures_return_the_exact_original_rows(self):
        original = {"include": [row("second", 2), row("first", 1)]}
        failures = [
            OSError("no nix"),
            RuntimeError("query failed"),
            subprocess.TimeoutExpired("nix", 30),
        ]
        for failure in failures:
            with (
                self.subTest(failure=failure),
                tempfile.TemporaryDirectory() as directory,
            ):
                output = Path(directory) / "output"
                summary = Path(directory) / "summary"
                with (
                    patch.dict(
                        os.environ,
                        {
                            "HESTIA_MATRIX": json.dumps(original),
                            "HESTIA_ANY_JOBS": "true",
                            "SYSTEM": "x86_64-linux",
                            "GITHUB_OUTPUT": str(output),
                            "GITHUB_STEP_SUMMARY": str(summary),
                        },
                        clear=True,
                    ),
                    patch(
                        "optimize_hestia_matrix.collect_group_plans",
                        side_effect=failure,
                    ),
                    patch("sys.stdout", new=StringIO()),
                ):
                    main()
                self.assertEqual(
                    json.loads(output.read_text().removeprefix("matrix=")), original
                )
                self.assertIn("Status: fallback", summary.read_text())

    def test_summary_measures_collection_and_grouping(self):
        original = {"include": [row("first", 1), row("second", 2)]}
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "output"
            summary = Path(directory) / "summary"
            with (
                patch.dict(
                    os.environ,
                    {
                        "HESTIA_MATRIX": json.dumps(original),
                        "HESTIA_ANY_JOBS": "true",
                        "SYSTEM": "x86_64-linux",
                        "GITHUB_OUTPUT": str(output),
                        "GITHUB_STEP_SUMMARY": str(summary),
                        "MATRIX_OPTIMIZER_MIN_SHARED_DERIVATIONS": "1",
                    },
                    clear=True,
                ),
                patch(
                    "optimize_hestia_matrix.collect_group_plans",
                    return_value=[frozenset({"shared"})] * 2,
                ) as collect,
                patch(
                    "optimize_hestia_matrix.time.monotonic", side_effect=[10.0, 10.125]
                ),
            ):
                main()
            self.assertEqual(collect.call_args.kwargs["min_shared_derivations"], 1)
            self.assertEqual(
                len(json.loads(output.read_text().removeprefix("matrix="))["include"]),
                1,
            )
            self.assertIn("Planning and grouping: 125 ms", summary.read_text())


if __name__ == "__main__":
    unittest.main()
