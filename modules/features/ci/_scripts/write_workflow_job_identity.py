#!/usr/bin/env python3

"""Write a structured identity for a workflow job."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from ci_telemetry import atomic_write_json, document


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--role", required=True, choices=("flake-eval",))
    parser.add_argument("--system", required=True)
    parser.add_argument("--runner-name", required=True)
    parser.add_argument("--output", required=True, type=Path)
    arguments = parser.parse_args()
    atomic_write_json(
        arguments.output,
        document(
            "workflow_job",
            arguments.system,
            {"role": arguments.role, "runner_name": arguments.runner_name},
        ),
    )


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
