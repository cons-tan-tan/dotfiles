from __future__ import annotations

import copy
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from ortools.sat.python import cp_model

SCRIPT_DIR = Path(__file__).parents[1] / "_scripts"
sys.path.insert(0, str(SCRIPT_DIR))

from plan_ci_matrix import (  # noqa: E402
    CostModel,
    RunTelemetry,
    Timing,
    WorkUnit,
    aggregate_timing,
    compatible_history,
    create_plan,
    rollout_decision,
    solve_schedule,
)


def identity(number: int) -> str:
    return f"{number:032d}"


def unit(
    number: int, dependencies: set[str], *, system: str = "x86_64-linux"
) -> WorkUnit:
    return WorkUnit(
        unit_id=f"unit-{number}",
        system=system,
        runner_labels=("ubuntu-latest",),
        member_check_ids=(f"{system}:check-{number}",),
        display_names=(f"check-{number}",),
        root_drv_ids=(identity(100 + number),),
        dependency_drv_ids=frozenset(dependencies),
        affinity_groups=("group",),
    )


def cost_model(dependencies: set[str], *, fixed: int = 1, cost: int = 100) -> CostModel:
    return CostModel(
        dependency_cost_ms={
            "x86_64-linux": {f"dep-{value}": cost for value in dependencies}
        },
        dependency_key_by_id={
            "x86_64-linux": {value: f"dep-{value}" for value in dependencies}
        },
        default_dependency_cost_ms={"x86_64-linux": cost},
        fixed_job_cost_ms={"x86_64-linux": fixed},
        sample_count_by_system={"x86_64-linux": len(dependencies)},
        dependency_sample_count_by_system={
            "x86_64-linux": {f"dep-{value}": 1 for value in dependencies}
        },
    )


def timing(*, flake: int = 0) -> Timing:
    return Timing(
        sample_count=1,
        observed_duration_ms=0,
        workflow_queue_ms=0,
        flake_start_ms=0,
        flake_eval_ms=flake,
        required_dispatch_ms=0,
        required_ms=0,
        evaluate_start_ms={"x86_64-linux": 0},
        evaluate_ms={"x86_64-linux": 0},
        dispatch_ms={"x86_64-linux": 0},
        result_dispatch_ms={"x86_64-linux": 0},
        result_ms={"x86_64-linux": 0},
        wrapper_overhead_ms={"x86_64-linux": ()},
    )


def telemetry() -> RunTelemetry:
    dependency = identity(1)
    root = identity(101)
    system = "x86_64-linux"
    check_id = f"{system}:check"
    lane = {
        "data": {
            "derivations": [
                {
                    "drv_id": dependency,
                    "drv_path": f"/nix/store/{dependency}-dependency.drv",
                }
            ],
            "checks": [
                {
                    "check_id": check_id,
                    "display_name": "check",
                    "drv_id": root,
                    "runner_labels": ["ubuntu-latest"],
                    "static_affinity_group": "quality",
                    "selection": "scheduled",
                    "plan": {
                        "status": "success",
                        "dependency_drv_ids": [dependency],
                    },
                }
            ],
            "decision": {
                "jobs": [
                    {
                        "job_id": "job-1",
                        "name": "quality",
                        "runner_labels": ["ubuntu-latest"],
                        "member_check_ids": [check_id],
                        "root_drv_ids": [root],
                        "planned_drv_ids": [dependency],
                    }
                ]
            },
        }
    }
    bundle = {
        "data": {
            "lane": lane,
            "jobs": [
                {
                    "data": {
                        "job_id": "job-1",
                        "name": "quality",
                        "status": "success",
                        "phases": {
                            "github_job_setup": {"duration_ms": 10},
                            "prefetch": {"duration_ms": 10},
                            "nix_build": {"duration_ms": 100},
                        },
                        "derivation_events": [
                            {
                                "drv_id": dependency,
                                "outcome": "completed",
                                "duration_ms": 100,
                            }
                        ],
                        "total_duration_ms": 120,
                    }
                }
            ],
        }
    }
    return RunTelemetry(
        directory=Path("."),
        index={
            "source": {
                "repository": "owner/repo",
                "run_id": "1",
                "run_attempt": 1,
                "head_sha": "a" * 40,
                "created_at": "2026-08-06T00:00:00Z",
            }
        },
        bundles={system: bundle},
    )


class PlannerSolverTests(unittest.TestCase):
    def test_excludes_history_from_another_runner_class(self) -> None:
        target = telemetry()
        previous_bundles = copy.deepcopy(target.bundles)
        previous_bundles["x86_64-linux"]["data"]["lane"]["data"]["decision"]["jobs"][0][
            "runner_labels"
        ] = ["self-hosted"]
        previous = RunTelemetry(
            directory=Path("previous"),
            index=target.index,
            bundles=previous_bundles,
        )

        self.assertEqual(compatible_history([target, previous], target), [target])

    @unittest.skipUnless(
        shutil.which("check-jsonschema"), "check-jsonschema unavailable"
    )
    def test_generated_plan_matches_the_published_schema(self) -> None:
        run = telemetry()
        rerun_index = copy.deepcopy(run.index)
        rerun_index["source"]["run_attempt"] = 2
        rerun = RunTelemetry(
            directory=Path("rerun"),
            index=rerun_index,
            bundles=run.bundles,
        )
        plan = create_plan(
            target=run,
            history=[run, rerun],
            timing=timing(),
            max_jobs_per_system=1,
            makespan_slack_ms=0,
            solver_time_limit_seconds=3,
            robust_quantile=0.75,
            minimum_history_runs=2,
            minimum_dependency_samples=2,
        )
        self.assertEqual(
            plan["source"]["history_samples"],
            [
                {"run_id": "1", "run_attempt": 1},
                {"run_id": "1", "run_attempt": 2},
            ],
        )
        schema = SCRIPT_DIR.parent / "_schemas" / "ci-optimization-v1.schema.json"
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "plan.json"
            output.write_text(json.dumps(plan))
            subprocess.run(
                [
                    "check-jsonschema",
                    "--schemafile",
                    str(schema),
                    str(output),
                ],
                check=True,
                capture_output=True,
                text=True,
            )

    def test_rollout_requires_cost_coverage_and_primary_objective_proofs(
        self,
    ) -> None:
        ready, reason = rollout_decision(
            has_work=True,
            usable_sample_count=10,
            minimum_history_runs=10,
            coverage_complete=False,
            stage_statuses=("optimal", "optimal", "unknown"),
        )
        self.assertFalse(ready)
        self.assertEqual(reason, "insufficient_cost_coverage")

        ready, reason = rollout_decision(
            has_work=True,
            usable_sample_count=10,
            minimum_history_runs=10,
            coverage_complete=True,
            stage_statuses=("optimal", "optimal", "unknown"),
        )
        self.assertTrue(ready)
        self.assertEqual(reason, "shadow_only")

    def test_aggregates_only_compatible_timing_samples_once(self) -> None:
        target = timing(flake=100)
        target.wrapper_overhead_ms["x86_64-linux"] = (11,)
        compatible = timing(flake=300)
        compatible.wrapper_overhead_ms["x86_64-linux"] = (22, 33)
        incompatible = Timing(
            sample_count=1,
            observed_duration_ms=0,
            workflow_queue_ms=0,
            flake_start_ms=0,
            flake_eval_ms=900,
            required_dispatch_ms=0,
            required_ms=0,
            evaluate_start_ms={"aarch64-darwin": 0},
            evaluate_ms={"aarch64-darwin": 0},
            dispatch_ms={"aarch64-darwin": 0},
            result_dispatch_ms={"aarch64-darwin": 0},
            result_ms={"aarch64-darwin": 0},
            wrapper_overhead_ms={"aarch64-darwin": (99,)},
        )

        result = aggregate_timing(
            target,
            [target, compatible, incompatible],
            robust_quantile=0.75,
        )

        self.assertEqual(result.sample_count, 2)
        self.assertEqual(result.flake_eval_ms, 300)
        self.assertEqual(result.wrapper_overhead_ms["x86_64-linux"], (11, 22, 33))

    def test_splits_work_to_minimize_the_critical_path(self) -> None:
        dependencies = {identity(index) for index in range(4)}
        units = [unit(index, {identity(index)}) for index in range(4)]
        result = solve_schedule(
            units,
            cost_model(dependencies),
            timing=timing(),
            max_jobs_per_system=2,
            makespan_slack_ms=0,
            time_limit_seconds=3,
        )

        self.assertEqual(len(result.jobs), 2)
        self.assertEqual(
            sorted(len(job.member_check_ids) for job in result.jobs), [2, 2]
        )
        self.assertEqual(result.makespan_before_required_ms, 201)
        self.assertTrue(all(status == "optimal" for status in result.stage_statuses))

    def test_keeps_the_primary_solution_when_runner_optimization_times_out(
        self,
    ) -> None:
        class UnknownSolver:
            def __init__(self) -> None:
                self.parameters = mock.Mock()

            def Solve(self, _model: object) -> int:
                return cp_model.UNKNOWN

            def WallTime(self) -> float:
                return 0

        dependency = identity(1)
        solvers = [cp_model.CpSolver(), UnknownSolver()]
        with mock.patch("plan_ci_matrix.cp_model.CpSolver", side_effect=solvers):
            result = solve_schedule(
                [unit(1, {dependency})],
                cost_model({dependency}),
                timing=timing(),
                max_jobs_per_system=1,
                makespan_slack_ms=0,
                time_limit_seconds=3,
            )

        self.assertEqual(result.stage_statuses, ("optimal", "unknown"))
        self.assertEqual(len(result.jobs), 1)

    def test_merges_when_flake_eval_hides_the_extra_job_time(self) -> None:
        left = identity(1)
        right = identity(2)
        result = solve_schedule(
            [unit(1, {left}), unit(2, {right})],
            cost_model({left, right}, fixed=10),
            timing=timing(flake=250),
            max_jobs_per_system=2,
            makespan_slack_ms=0,
            time_limit_seconds=3,
        )

        self.assertEqual(result.makespan_before_required_ms, 250)
        self.assertEqual(len(result.jobs), 1)
        self.assertEqual(result.total_runner_ms, 210)

    def test_shared_dependency_is_charged_once_inside_a_job(self) -> None:
        shared = identity(1)
        result = solve_schedule(
            [unit(1, {shared}), unit(2, {shared})],
            cost_model({shared}, fixed=10),
            timing=timing(flake=200),
            max_jobs_per_system=2,
            makespan_slack_ms=0,
            time_limit_seconds=3,
        )

        self.assertEqual(len(result.jobs), 1)
        self.assertEqual(result.jobs[0].predicted_duration_ms, 110)
        self.assertEqual(result.total_runner_ms, 110)


if __name__ == "__main__":
    unittest.main()
