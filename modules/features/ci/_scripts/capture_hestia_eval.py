#!/usr/bin/env python3

"""Stream nix-eval-jobs to Hestia while retaining its exact JSONL output."""

from __future__ import annotations

import json
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
        "--option",
        "stalled-download-timeout",
        "30",
        "--option",
        "download-attempts",
        "2",
        *arguments,
    ]


def capture(arguments: list[str], target: Path) -> int:
    target.parent.mkdir(parents=True, exist_ok=True)
    groups_by_drv: dict[str, set[str]] = {}
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
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                continue
            if not isinstance(record, dict):
                continue
            drv_path = record.get("drvPath")
            meta = record.get("meta")
            hestia = meta.get("hestia") if isinstance(meta, dict) else None
            group = hestia.get("group") if isinstance(hestia, dict) else None
            if isinstance(drv_path, str) and isinstance(group, str):
                groups_by_drv.setdefault(drv_path, set()).add(group)
        return_code = process.wait()

    # A partial capture is diagnostically valuable and is explicitly marked by
    # the lane producer when the child exits unsuccessfully.
    temporary.replace(target)
    conflicting_drv_paths = sorted(
        drv_path for drv_path, groups in groups_by_drv.items() if len(groups) > 1
    )
    if return_code == 0 and conflicting_drv_paths:
        print(
            "error: Hestia derivations have conflicting groups: "
            + json.dumps(conflicting_drv_paths),
            file=sys.stderr,
        )
        return 1
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
