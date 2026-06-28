#!/usr/bin/env python3
"""Generate Codex hook trust state for the Herdr SessionStart hook.

Codex computes hook trust hashes from its normalized hook identity. Keep that
logic in Codex by asking the app-server for hooks/list and re-key only the
absolute hooks.json path for the target home directory.
"""

from __future__ import annotations

import argparse
import json
import os
import select
import subprocess
import sys
import time
from typing import Any


def _send(proc: subprocess.Popen[str], message: dict[str, Any]) -> None:
    if proc.stdin is None:
        raise RuntimeError("codex app-server stdin is unavailable")
    proc.stdin.write(json.dumps(message) + "\n")
    proc.stdin.flush()


def read_response(
    proc: subprocess.Popen[str], request_id: int, timeout_sec: float = 10.0
) -> dict[str, Any]:
    if proc.stdout is None:
        raise RuntimeError("codex app-server stdout is unavailable")

    deadline = time.monotonic() + timeout_sec
    while time.monotonic() < deadline:
        remaining = max(0.0, deadline - time.monotonic())
        readable, _, _ = select.select([proc.stdout], [], [], remaining)
        if not readable:
            break

        line = proc.stdout.readline()
        if not line:
            break
        try:
            value = json.loads(line)
        except json.JSONDecodeError:
            continue
        if value.get("id") == request_id:
            if "error" in value:
                raise RuntimeError(value["error"])
            return value

    raise RuntimeError(f"timed out waiting for codex app-server response {request_id}")


def fetch_hooks_list(codex_bin: str, cwd: str) -> dict[str, Any]:
    proc = subprocess.Popen(
        [codex_bin, "app-server", "--listen", "stdio://"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    try:
        _send(
            proc,
            {
                "method": "initialize",
                "id": 1,
                "params": {
                    "clientInfo": {
                        "name": "dotfiles",
                        "title": "dotfiles",
                        "version": "0",
                    },
                    "capabilities": {"experimentalApi": True},
                },
            },
        )
        read_response(proc, 1)

        _send(proc, {"method": "initialized", "params": {}})
        _send(
            proc,
            {
                "method": "hooks/list",
                "id": 2,
                "params": {"cwds": [cwd]},
            },
        )
        return read_response(proc, 2)
    except Exception as exc:
        stderr = ""
        if proc.stderr is not None:
            try:
                proc.kill()
                proc.wait(timeout=5)
                stderr = proc.stderr.read()
            except Exception:
                pass
        if stderr:
            raise RuntimeError(f"{exc}; stderr={stderr}") from exc
        raise
    finally:
        if proc.stdin is not None:
            try:
                proc.stdin.close()
            except Exception:
                pass
        if proc.poll() is None:
            proc.kill()
        proc.wait()


def build_payload(
    hooks_list_response: dict[str, Any], hook_command: str, hooks_json_path: str
) -> dict[str, Any]:
    hooks = [
        hook
        for entry in hooks_list_response["result"]["data"]
        for hook in entry["hooks"]
        if hook.get("eventName") == "sessionStart"
        and hook.get("command") == hook_command
    ]
    if len(hooks) != 1:
        raise RuntimeError(f"expected exactly one Herdr Codex hook, found {len(hooks)}")

    hook = hooks[0]
    key_parts = hook["key"].split(":")
    if len(key_parts) < 4:
        raise RuntimeError(f"unexpected Codex hook key: {hook['key']}")

    state_suffix = ":".join(key_parts[-3:])
    state_key = f"{hooks_json_path}:{state_suffix}"
    return {
        "hooks": {
            "state": {
                state_key: {
                    "trusted_hash": hook["currentHash"],
                    "enabled": True,
                }
            }
        }
    }


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--codex-bin", required=True)
    parser.add_argument("--hook-command", required=True)
    parser.add_argument("--hooks-json-path", required=True)
    parser.add_argument("--cwd", default=os.getcwd())
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    hooks_list_response = fetch_hooks_list(args.codex_bin, args.cwd)
    payload = build_payload(
        hooks_list_response,
        hook_command=args.hook_command,
        hooks_json_path=args.hooks_json_path,
    )
    json.dump(payload, sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
