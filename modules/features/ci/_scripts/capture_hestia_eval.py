#!/usr/bin/env python3

"""Stream nix-eval-jobs to Hestia and reject conflicting group assignments."""

from __future__ import annotations

import json
import subprocess
import sys


def command(arguments: list[str]) -> list[str]:
    return [
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
        *arguments,
    ]


def capture(arguments: list[str]) -> int:
    groups_by_drv: dict[str, set[str]] = {}
    with subprocess.Popen(
        command(arguments),
        stdout=subprocess.PIPE,
        text=True,
        bufsize=1,
    ) as process:
        assert process.stdout is not None
        for line in process.stdout:
            sys.stdout.write(line)
            sys.stdout.flush()
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


if __name__ == "__main__":
    try:
        sys.exit(capture(sys.argv[1:]))
    except OSError as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
