#!/usr/bin/env python3

"""Stream nix-eval-jobs to Hestia while retaining its exact JSONL output."""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
from pathlib import Path


def command(arguments: list[str]) -> list[str]:
    return [
        "nix",
        "run",
        "nixpkgs#nix-eval-jobs",
        "--inputs-from",
        ".",
        "--",
        "--workers",
        "1",
        "--max-memory-size",
        "12288",
        *arguments,
    ]


def capture(arguments: list[str], target: Path) -> int:
    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        "w", encoding="utf-8", dir=target.parent, delete=False
    ) as output:
        temporary = Path(output.name)
        process = subprocess.Popen(
            command(arguments),
            stdout=subprocess.PIPE,
            text=True,
            bufsize=1,
        )
        assert process.stdout is not None
        for line in process.stdout:
            sys.stdout.write(line)
            sys.stdout.flush()
            output.write(line)
        return_code = process.wait()

    # A partial capture is diagnostically valuable and is explicitly marked by
    # the lane producer when the child exits unsuccessfully.
    temporary.replace(target)
    return return_code


def main() -> int:
    raw_target = os.environ.get("HESTIA_EVAL_CAPTURE")
    if not raw_target:
        print(
            "error: missing environment variable: HESTIA_EVAL_CAPTURE", file=sys.stderr
        )
        return 1
    return capture(sys.argv[1:], Path(raw_target))


if __name__ == "__main__":
    sys.exit(main())
