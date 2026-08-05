#!/usr/bin/env python3

"""Validate and normalize the matrix emitted by Hestia."""

import json
import os
import re
import sys

UINT64_MAX = 18_446_744_073_709_551_615


def require_env(name: str) -> str:
    value = os.environ.get(name)
    if value is None:
        raise ValueError(f"missing environment variable: {name}")
    return value


def is_nonempty_string(value: object) -> bool:
    return isinstance(value, str) and bool(value)


def validate_row(row: object, expected_system: str) -> str:
    if not isinstance(row, dict):
        raise ValueError("Hestia matrix row must be an object")

    drv_path = row.get("drvPath")
    if not is_nonempty_string(drv_path):
        raise ValueError("Hestia matrix row has an invalid drvPath")

    labels = row.get("os")
    valid_labels = (
        isinstance(labels, list)
        and bool(labels)
        and all(is_nonempty_string(label) for label in labels)
    )
    if not (
        is_nonempty_string(row.get("name"))
        and valid_labels
        and is_nonempty_string(row.get("installables"))
    ):
        raise ValueError("Hestia matrix row has invalid build fields")

    if row.get("system") != expected_system:
        raise ValueError("Hestia matrix row belongs to another system")
    return drv_path


def validate_matrix(raw_matrix: str, any_jobs: str, expected_system: str) -> str:
    matrix = json.loads(raw_matrix)
    if not isinstance(matrix, dict) or not isinstance(matrix.get("include"), list):
        raise ValueError("Hestia matrix must contain an include array")

    rows = matrix["include"]
    expected_any_jobs = "true" if rows else "false"
    if any_jobs != expected_any_jobs:
        raise ValueError("Hestia any-jobs output does not match its matrix")
    if len(rows) > 256:
        raise ValueError("Hestia matrix exceeds 256 rows")

    drv_paths = [validate_row(row, expected_system) for row in rows]
    if len(drv_paths) != len(set(drv_paths)):
        raise ValueError("Hestia matrix contains duplicate drvPaths")
    return json.dumps({"include": rows}, ensure_ascii=False, separators=(",", ":"))


def validate_manifest_version(raw_version: str, any_jobs: str) -> str:
    if not re.fullmatch(r"0|[1-9][0-9]*", raw_version):
        raise ValueError("Hestia manifest version is invalid for its matrix")
    version = int(raw_version)
    if version > UINT64_MAX or (any_jobs == "true" and version == 0):
        raise ValueError("Hestia manifest version is invalid for its matrix")
    return raw_version


def validate_output_limit(raw_limit: str) -> int:
    if not re.fullmatch(r"[1-9][0-9]*", raw_limit):
        raise ValueError("invalid Hestia matrix output limit")
    return int(raw_limit)


def main() -> None:
    any_jobs = require_env("HESTIA_ANY_JOBS")
    matrix = validate_matrix(
        require_env("HESTIA_MATRIX"),
        any_jobs,
        require_env("SYSTEM"),
    )
    manifest_version = validate_manifest_version(
        require_env("HESTIA_MANIFEST_VERSION"), any_jobs
    )
    output_limit = validate_output_limit(
        os.environ.get("MATRIX_OUTPUT_MAX_CHARS", "499000")
    )
    if len(matrix) > output_limit:
        raise ValueError("Hestia matrix exceeds the GitHub job output limit")

    with open(require_env("GITHUB_OUTPUT"), "a", encoding="utf-8") as output:
        output.write(f"matrix={matrix}\n")
        output.write(f"any-jobs={any_jobs}\n")
        output.write(f"manifest-version={manifest_version}\n")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
