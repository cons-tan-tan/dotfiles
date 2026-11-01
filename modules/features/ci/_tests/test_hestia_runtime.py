#!/usr/bin/env python3

"""Contracts retained when removing the CI telemetry wrappers."""

from __future__ import annotations

import subprocess
import sys
import unittest
from io import StringIO
from pathlib import Path
from unittest.mock import patch

SCRIPT_DIR = Path(__file__).parents[1] / "_scripts"
sys.path.insert(0, str(SCRIPT_DIR))

from capture_hestia_eval import capture, command
from run_hestia_build import run_build, run_matrix_build, run_prefetch


class EvaluationTests(unittest.TestCase):
    def run_capture(self, stream, exit_code=0):
        with (
            patch("capture_hestia_eval.subprocess.Popen") as popen,
            patch("capture_hestia_eval.sys.stdout", new=StringIO()) as output,
            patch("capture_hestia_eval.sys.stderr", new=StringIO()) as error,
        ):
            process = popen.return_value.__enter__.return_value
            process.stdout = StringIO(stream)
            process.wait.return_value = exit_code
            code = capture(["--flake", ".#checks"])
            self.assertEqual(popen.call_args.args[0], command(["--flake", ".#checks"]))
            return code, output.getvalue(), error.getvalue()

    def test_stream_is_preserved_including_non_record_lines(self):
        stream = '{"attr":"quality"}\n\nnot-json\n[]\n'
        code, output, error = self.run_capture(stream)
        self.assertEqual((code, output, error), (0, stream, ""))

    def test_evaluation_resource_and_network_limits_are_preserved(self):
        self.assertEqual(
            command([]),
            [
                "nix",
                "run",
                "nix-eval-jobs#nix-eval-jobs",
                "--inputs-from",
                ".",
                "--",
                "--workers",
                "1",
                "--max-memory-size",
                "12288",
                "--option",
                "stalled-download-timeout",
                "30",
                "--option",
                "filetransfer-retry-attempts",
                "2",
            ],
        )

    def test_conflicting_groups_fail_after_streaming_and_keep_child_failure(self):
        stream = (
            '{"drvPath":"/nix/store/shared.drv","meta":{"hestia":{"group":"first"}}}\n'
            '{"drvPath":"/nix/store/shared.drv","meta":{"hestia":{"group":"second"}}}\n'
        )
        code, output, error = self.run_capture(stream)
        self.assertEqual((code, output), (1, stream))
        self.assertIn("Hestia derivations have conflicting groups", error)
        self.assertEqual(self.run_capture(stream, exit_code=42)[0], 42)

    def test_aliases_in_the_same_group_are_allowed(self):
        line = (
            '{"drvPath":"/nix/store/shared.drv","meta":{"hestia":{"group":"first"}}}\n'
        )
        self.assertEqual(self.run_capture(line + line)[0], 0)


class BuildTests(unittest.TestCase):
    def test_prefetch_and_build_receive_every_installable(self):
        installables = ["/nix/store/first.drv^*", "/nix/store/second.drv^*"]
        with patch(
            "run_hestia_build.subprocess.run",
            return_value=subprocess.CompletedProcess([], 42),
        ) as run:
            self.assertEqual(run_prefetch("/bin/hestia", installables), 42)
            run.assert_called_once_with(
                ["/bin/hestia", "prefetch", *installables], check=False
            )
            run.reset_mock()
            self.assertEqual(run_build(installables), 42)
            run.assert_called_once_with(
                ["nix", "build", "--no-link", *installables], check=False
            )

    def test_prefetch_failure_falls_back_and_build_status_is_preserved(self):
        installables = ["/nix/store/root.drv^*"]
        for prefetch_code, build_code in ((42, 0), (0, 42), (42, 42), (0, 0)):
            with (
                self.subTest(prefetch=prefetch_code, build=build_code),
                patch("run_hestia_build.run_prefetch", return_value=prefetch_code),
                patch("run_hestia_build.run_build", return_value=build_code) as build,
                patch("run_hestia_build.sys.stderr", new=StringIO()) as error,
            ):
                self.assertEqual(
                    run_matrix_build("/bin/hestia", installables), build_code
                )
                build.assert_called_once_with(installables)
                self.assertEqual(
                    "falling back to normal Nix substitution" in error.getvalue(),
                    prefetch_code != 0,
                )

    def test_prefetch_spawn_failure_does_not_hide_broken_setup(self):
        with (
            patch("run_hestia_build.run_prefetch", side_effect=OSError("missing")),
            patch("run_hestia_build.run_build") as build,
            self.assertRaises(OSError),
        ):
            run_matrix_build("/bin/hestia", ["/nix/store/root.drv^*"])
        build.assert_not_called()


if __name__ == "__main__":
    unittest.main()
