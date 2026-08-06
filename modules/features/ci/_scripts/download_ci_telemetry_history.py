#!/usr/bin/env python3

"""Download a bounded, trusted history window of collected CI telemetry."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import zipfile
from pathlib import Path, PurePosixPath

from capture_workflow_timing import capture
from ci_telemetry import PRODUCER_NAME, atomic_write_json, read_document
from collect_ci_telemetry import INDEX_SCHEMA_ID, validate_run_index

ARTIFACT_PATTERN = re.compile(
    r"^ci-telemetry-run-v1-source-([1-9][0-9]*)-([1-9][0-9]*)-collector-([1-9][0-9]*)-([1-9][0-9]*)$"
)
MAX_ARCHIVE_BYTES = 100 * 1024 * 1024
MAX_EXTRACTED_BYTES = 200 * 1024 * 1024
MAX_ARCHIVE_ENTRIES = 32
REPOSITORY_PATTERN = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
HISTORY_TIMEOUT_SECONDS = 5 * 60


def remaining_timeout(deadline: float, maximum: float) -> float:
    remaining = deadline - time.monotonic()
    if remaining <= 1:
        raise RuntimeError("CI telemetry history deadline expired")
    return min(maximum, remaining)


def gh_json(arguments: list[str], *, timeout: float = 60) -> dict[str, object]:
    # GitHub-hosted runners guarantee the built-in `gh api`, not the local
    # read-only extension.  Pin the HTTP method so this path cannot mutate.
    result = subprocess.run(
        ["gh", "api", "--method", "GET", *arguments],
        check=False,
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    if result.returncode != 0:
        detail = result.stderr.strip().splitlines()
        suffix = f": {detail[-1]}" if detail else ""
        raise RuntimeError(f"GitHub artifact query failed{suffix}")
    value = json.loads(result.stdout)
    if not isinstance(value, dict):
        raise ValueError("invalid GitHub artifact response")
    return value


def list_artifacts(
    repository: str, page_limit: int = 3, *, deadline: float | None = None
) -> list[dict[str, object]]:
    selected: dict[int, dict[str, object]] = {}
    for page in range(1, page_limit + 1):
        timeout = 60 if deadline is None else remaining_timeout(deadline, 60)
        response = gh_json(
            [f"/repos/{repository}/actions/artifacts?per_page=100&page={page}"],
            timeout=timeout,
        )
        artifacts = response.get("artifacts")
        if not isinstance(artifacts, list):
            raise ValueError("GitHub artifact response has no artifact list")
        for raw in artifacts:
            if not isinstance(raw, dict):
                continue
            name = raw.get("name")
            artifact_id = raw.get("id")
            size = raw.get("size_in_bytes")
            match = ARTIFACT_PATTERN.fullmatch(name) if isinstance(name, str) else None
            workflow_run = raw.get("workflow_run")
            if (
                match is not None
                and isinstance(artifact_id, int)
                and not isinstance(artifact_id, bool)
                and isinstance(size, int)
                and not isinstance(size, bool)
                and 0 < size <= MAX_ARCHIVE_BYTES
                and raw.get("expired") is False
                and isinstance(workflow_run, dict)
                and workflow_run.get("id") == int(match.group(3))
            ):
                selected[artifact_id] = raw
        if len(artifacts) < 100:
            break
    return sorted(
        selected.values(),
        key=lambda item: str(item.get("created_at", "")),
        reverse=True,
    )


def artifact_identity(
    artifact: dict[str, object],
) -> tuple[tuple[str, int], tuple[str, int]]:
    match = ARTIFACT_PATTERN.fullmatch(str(artifact.get("name", "")))
    if match is None:
        raise ValueError("invalid telemetry artifact name")
    return (
        (match.group(1), int(match.group(2))),
        (match.group(3), int(match.group(4))),
    )


def trusted_collector_run(
    repository: str,
    run_id: str,
    run_attempt: int,
    *,
    timeout: float = 60,
) -> str | None:
    run = gh_json(
        [f"/repos/{repository}/actions/runs/{run_id}/attempts/{run_attempt}"],
        timeout=timeout,
    )
    raw_path = run.get("path")
    path = str(raw_path).split("@", 1)[0] if isinstance(raw_path, str) else ""
    source_repository = run.get("repository")
    head_sha = run.get("head_sha")
    trusted = (
        run.get("name") == "CI telemetry"
        and path == ".github/workflows/ci-telemetry.yaml"
        and run.get("event") == "workflow_run"
        and run.get("head_branch") == "main"
        and run.get("run_attempt") == run_attempt
        and run.get("status") == "completed"
        and run.get("conclusion") == "success"
        and isinstance(head_sha, str)
        and re.fullmatch(r"[0-9a-f]{40}", head_sha) is not None
        and isinstance(source_repository, dict)
        and source_repository.get("full_name") == repository
    )
    return head_sha if trusted else None


def download_artifact(
    repository: str, artifact_id: int, output: Path, *, timeout: float = 120
) -> None:
    with output.open("wb") as destination:
        result = subprocess.run(
            [
                "gh",
                "api",
                "--method",
                "GET",
                f"/repos/{repository}/actions/artifacts/{artifact_id}/zip",
            ],
            check=False,
            stdout=destination,
            stderr=subprocess.PIPE,
            timeout=timeout,
        )
    if result.returncode != 0:
        detail = result.stderr.decode(errors="replace").strip().splitlines()
        suffix = f": {detail[-1]}" if detail else ""
        raise RuntimeError(f"GitHub artifact download failed{suffix}")
    if output.stat().st_size > MAX_ARCHIVE_BYTES:
        raise ValueError("downloaded artifact exceeds the size limit")


def safe_extract(archive: Path, output: Path) -> None:
    with zipfile.ZipFile(archive) as source:
        entries = source.infolist()
        if not entries or len(entries) > MAX_ARCHIVE_ENTRIES:
            raise ValueError("telemetry artifact has an invalid inventory")
        if sum(entry.file_size for entry in entries) > MAX_EXTRACTED_BYTES:
            raise ValueError("telemetry artifact exceeds the extracted size limit")
        for entry in entries:
            path = PurePosixPath(entry.filename)
            mode = entry.external_attr >> 16
            if (
                path.is_absolute()
                or ".." in path.parts
                or not path.parts
                or stat.S_ISLNK(mode)
                or (mode and not (stat.S_ISREG(mode) or stat.S_ISDIR(mode)))
            ):
                raise ValueError("telemetry artifact contains an unsafe entry")
        source.extractall(output)


def expected_bundle_run(source: dict[str, object], system: str) -> dict[str, object]:
    return {
        "repository": source["repository"],
        "repository_id": source["repository_id"],
        "run_id": source["run_id"],
        "run_attempt": source["run_attempt"],
        "workflow": source["workflow_name"],
        "event": source["event"],
        "ref": f"refs/heads/{source['head_branch']}",
        "commit_sha": source["head_sha"],
        "system": system,
    }


def valid_artifact_inventory(directory: Path, index: dict[str, object]) -> bool:
    try:
        validate_run_index(index)
        if set(index) != {
            "$schema",
            "schema_version",
            "document_type",
            "producer",
            "observed_at",
            "source",
            "collector",
            "artifact_download_status",
            "collection_status",
            "expected_systems",
            "systems",
        }:
            return False
        if (
            index.get("$schema") != INDEX_SCHEMA_ID
            or index.get("schema_version") != 1
            or index.get("document_type") != "run_index"
        ):
            return False
        producer = index.get("producer")
        if (
            not isinstance(producer, dict)
            or set(producer) != {"name", "version"}
            or producer.get("name") != PRODUCER_NAME
            or not isinstance(producer.get("version"), str)
            or not producer.get("version")
        ):
            return False
        source = index.get("source")
        entries = index.get("systems")
        if not isinstance(source, dict) or not isinstance(entries, list):
            return False
        expected_files = {
            "index.json",
            "schemas/telemetry-run-index-v1.schema.json",
            "schemas/telemetry-v1.schema.json",
        }
        for raw_entry in entries:
            if not isinstance(raw_entry, dict):
                return False
            system = raw_entry.get("system")
            relative = raw_entry.get("bundle_path")
            digest = raw_entry.get("bundle_sha256")
            if (
                not isinstance(system, str)
                or relative != f"systems/{system}.json"
                or not isinstance(digest, str)
                or raw_entry.get("artifact_status") != "available"
                or raw_entry.get("bundle_collection_status") != "complete"
            ):
                return False
            expected_files.add(relative)
            bundle_path = directory / relative
            if (
                not bundle_path.is_file()
                or hashlib.sha256(bundle_path.read_bytes()).hexdigest() != digest
            ):
                return False
            bundle = read_document(bundle_path, "bundle")
            if bundle.get("run") != expected_bundle_run(source, system):
                return False
            data = bundle.get("data")
            if (
                not isinstance(data, dict)
                or data.get("collection_status") != "complete"
            ):
                return False
        actual_files = {
            path.relative_to(directory).as_posix()
            for path in directory.rglob("*")
            if path.is_file()
        }
        return actual_files == expected_files
    except (
        AssertionError,
        KeyError,
        RecursionError,
        UnicodeError,
        json.JSONDecodeError,
        OSError,
        ValueError,
    ):
        return False


def timing_matches_run(
    path: Path,
    repository: str,
    source_identity: tuple[str, int],
    commit_sha: object,
) -> bool:
    try:
        timing = json.loads(path.read_text())
    except (json.JSONDecodeError, OSError):
        return False
    return (
        isinstance(timing, dict)
        and timing.get("schema_version") == 1
        and timing.get("document_type") == "workflow_timing"
        and timing.get("repository") == repository
        and str(timing.get("run_id")) == source_identity[0]
        and timing.get("run_attempt") == source_identity[1]
        and timing.get("commit_sha") == commit_sha
    )


def valid_run(
    directory: Path,
    repository: str,
    *,
    expected_source: tuple[str, int] | None = None,
    expected_collector: tuple[str, int, str] | None = None,
) -> tuple[str, int] | None:
    try:
        index = json.loads((directory / "index.json").read_text())
    except (json.JSONDecodeError, OSError):
        return None
    if not isinstance(index, dict) or index.get("collection_status") != "complete":
        return None
    source = index.get("source")
    if not isinstance(source, dict):
        return None
    if set(source) != {
        "repository",
        "repository_id",
        "workflow_id",
        "workflow_name",
        "workflow_path",
        "run_id",
        "run_attempt",
        "event",
        "head_sha",
        "head_branch",
        "conclusion",
        "created_at",
        "run_started_at",
        "updated_at",
        "trust_tier",
    }:
        return None
    run_id = source.get("run_id")
    attempt = source.get("run_attempt")
    if (
        source.get("repository") != repository
        or source.get("conclusion") != "success"
        or source.get("trust_tier") != "trusted_default_branch"
        or source.get("workflow_name") != "CI"
        or source.get("workflow_path") != ".github/workflows/ci.yaml"
        or source.get("event") not in {"push", "workflow_dispatch"}
        or source.get("head_branch") != "main"
        or re.fullmatch(r"[0-9a-f]{40}", str(source.get("head_sha", ""))) is None
        or not isinstance(source.get("repository_id"), str)
        or not source.get("repository_id")
        or not isinstance(source.get("workflow_id"), str)
        or not source.get("workflow_id")
        or not isinstance(run_id, str)
        or re.fullmatch(r"[1-9][0-9]*", run_id) is None
        or not isinstance(attempt, int)
        or isinstance(attempt, bool)
        or attempt < 1
    ):
        return None
    collector = index.get("collector")
    if (
        not isinstance(collector, dict)
        or set(collector) != {"run_id", "run_attempt", "commit_sha"}
        or re.fullmatch(r"[1-9][0-9]*", str(collector.get("run_id", ""))) is None
        or not isinstance(collector.get("run_attempt"), int)
        or isinstance(collector.get("run_attempt"), bool)
        or int(collector["run_attempt"]) < 1
        or re.fullmatch(r"[0-9a-f]{40}", str(collector.get("commit_sha", ""))) is None
    ):
        return None
    source_identity = (run_id, attempt)
    if expected_source is not None and source_identity != expected_source:
        return None
    if expected_collector is not None:
        collector_attempt = collector.get("run_attempt")
        if (
            str(collector.get("run_id")) != expected_collector[0]
            or collector_attempt != expected_collector[1]
            or collector.get("commit_sha") != expected_collector[2]
        ):
            return None
    if not valid_artifact_inventory(directory, index):
        return None
    return source_identity


def copy_current(
    current: Path, current_timing: Path, output: Path, repository: str
) -> tuple[str, int]:
    identity = valid_run(current, repository)
    if identity is None:
        raise ValueError("current telemetry is not a complete successful run")
    index = json.loads((current / "index.json").read_text())
    source = index.get("source") if isinstance(index, dict) else None
    if not isinstance(source, dict) or not timing_matches_run(
        current_timing,
        repository,
        identity,
        source.get("head_sha"),
    ):
        raise ValueError("current workflow timing belongs to another run attempt")
    shutil.copytree(current, output / "current")
    shutil.copyfile(current_timing, output / "current" / "workflow-timing.json")
    return identity


def collect_history(
    *,
    repository: str,
    current: Path,
    current_timing: Path,
    output: Path,
    maximum_runs: int,
    history_timeout_seconds: int = HISTORY_TIMEOUT_SECONDS,
) -> int:
    if output.exists():
        raise ValueError("history output already exists")
    output.mkdir(parents=True)
    current_index = json.loads((current / "index.json").read_text())
    current_source = (
        current_index.get("source") if isinstance(current_index, dict) else None
    )
    if (
        not isinstance(current_source, dict)
        or current_source.get("repository") != repository
    ):
        raise ValueError("current telemetry repository mismatch")
    current_identity = copy_current(current, current_timing, output, repository)
    accepted = {current_identity}
    if maximum_runs == 1:
        return 1

    deadline = time.monotonic() + history_timeout_seconds
    try:
        artifacts = list_artifacts(repository, deadline=deadline)
    except (
        json.JSONDecodeError,
        OSError,
        RuntimeError,
        subprocess.TimeoutExpired,
        ValueError,
    ) as error:
        print(f"::warning::CI telemetry history is unavailable: {error}")
        return 1

    attempts = 0
    for artifact in artifacts:
        if len(accepted) >= maximum_runs or attempts >= maximum_runs * 4:
            break
        if deadline - time.monotonic() <= 1:
            print("::warning::CI telemetry history deadline expired")
            break
        attempts += 1
        artifact_id = int(artifact["id"])
        try:
            source_identity, collector_identity = artifact_identity(artifact)
            collector_sha = trusted_collector_run(
                repository,
                collector_identity[0],
                collector_identity[1],
                timeout=remaining_timeout(deadline, 60),
            )
            if collector_sha is None:
                continue
            with tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                archive = root / "artifact.zip"
                extracted = root / "extracted"
                extracted.mkdir()
                download_artifact(
                    repository,
                    artifact_id,
                    archive,
                    timeout=remaining_timeout(deadline, 120),
                )
                safe_extract(archive, extracted)
                identity = valid_run(
                    extracted,
                    repository,
                    expected_source=source_identity,
                    expected_collector=(
                        collector_identity[0],
                        collector_identity[1],
                        collector_sha,
                    ),
                )
                if identity is None or identity in accepted:
                    continue
                timing = capture(
                    repository,
                    identity[0],
                    identity[1],
                    timeout=remaining_timeout(deadline, 60),
                )
                destination = output / f"run-{identity[0]}-{identity[1]}"
                shutil.copytree(extracted, destination)
                atomic_write_json(
                    destination / "workflow-timing.json",
                    timing,
                )
                accepted.add(identity)
        except (
            KeyError,
            RecursionError,
            UnicodeError,
            json.JSONDecodeError,
            OSError,
            RuntimeError,
            subprocess.TimeoutExpired,
            ValueError,
            zipfile.BadZipFile,
        ) as error:
            print(f"::warning::Ignoring telemetry artifact {artifact_id}: {error}")
    return len(accepted)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repository", required=True)
    parser.add_argument("--current", required=True, type=Path)
    parser.add_argument("--current-timing", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--maximum-runs", type=int, default=10)
    arguments = parser.parse_args()
    if REPOSITORY_PATTERN.fullmatch(arguments.repository) is None:
        raise ValueError("invalid repository")
    if not 1 <= arguments.maximum_runs <= 100:
        raise ValueError("maximum runs must be between 1 and 100")
    count = collect_history(
        repository=arguments.repository,
        current=arguments.current,
        current_timing=arguments.current_timing,
        output=arguments.output,
        maximum_runs=arguments.maximum_runs,
    )
    print(f"Collected {count} usable CI telemetry run(s).")


if __name__ == "__main__":
    try:
        main()
    except (
        KeyError,
        RecursionError,
        UnicodeError,
        json.JSONDecodeError,
        OSError,
        ValueError,
    ) as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
