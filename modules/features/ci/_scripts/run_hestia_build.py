#!/usr/bin/env python3

"""Build the evaluated Hestia installables, retaining the prefetch fallback."""

from __future__ import annotations

import os
import shlex
import subprocess
import sys


def run_prefetch(hestia_bin: str, installables: list[str]) -> int:
    return subprocess.run(
        [hestia_bin, "prefetch", *installables], check=False
    ).returncode


def run_build(installables: list[str]) -> int:
    return subprocess.run(
        ["nix", "build", "--no-link", *installables], check=False
    ).returncode


def run_matrix_build(hestia_bin: str, installables: list[str]) -> int:
    # A completed prefetch failure is recoverable through normal substitution.
    # Spawn failures remain infrastructure errors rather than hiding broken setup.
    if run_prefetch(hestia_bin, installables) != 0:
        print(
            "::warning::Hestia closure prefetch failed; "
            "falling back to normal Nix substitution",
            file=sys.stderr,
        )
    return run_build(installables)


def required(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise ValueError(f"missing environment variable: {name}")
    return value


def main() -> int:
    installables = shlex.split(required("INSTALLABLES"))
    if not installables:
        raise ValueError("Hestia build has no installables")
    return run_matrix_build(required("HESTIA_BIN"), installables)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
