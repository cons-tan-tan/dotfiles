import importlib.util
import pathlib

import pytest


MODULE_PATH = pathlib.Path(__file__).with_name("generate_herdr_hook_state.py")
SPEC = importlib.util.spec_from_file_location("generate_herdr_hook_state", MODULE_PATH)
generate_herdr_hook_state = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(generate_herdr_hook_state)


def hooks_list_response(*hooks):
    return {
        "result": {
            "data": [
                {
                    "cwd": "/repo",
                    "hooks": list(hooks),
                    "warnings": [],
                    "errors": [],
                }
            ]
        }
    }


def hook(key, command, *, event_name="sessionStart", current_hash="sha256:abc"):
    return {
        "key": key,
        "eventName": event_name,
        "command": command,
        "currentHash": current_hash,
    }


def test_build_payload_rekeys_user_home_hooks_path():
    command = "/nix/store/env PATH=/nix/store/bin /nix/store/bash/bin/bash /home/me/.codex/herdr-agent-state.sh session"
    response = hooks_list_response(
        hook(
            "/tmp/build-home/.codex/hooks.json:session_start:0:0",
            "hcom codex-sessionstart",
            current_hash="sha256:hcom",
        ),
        hook(
            "/tmp/build-home/.codex/hooks.json:session_start:1:0",
            command,
            current_hash="sha256:herdr",
        ),
    )

    assert generate_herdr_hook_state.build_payload(
        response,
        hook_command=command,
        hooks_json_path="/home/me/.codex/hooks.json",
    ) == {
        "hooks": {
            "state": {
                "/home/me/.codex/hooks.json:session_start:1:0": {
                    "trusted_hash": "sha256:herdr",
                    "enabled": True,
                }
            }
        }
    }


def test_build_payload_requires_exactly_one_herdr_hook():
    response = hooks_list_response(
        hook("/tmp/home/.codex/hooks.json:session_start:0:0", "hcom codex-sessionstart")
    )

    with pytest.raises(RuntimeError, match="expected exactly one"):
        generate_herdr_hook_state.build_payload(
            response,
            hook_command="missing",
            hooks_json_path="/home/me/.codex/hooks.json",
        )


def test_build_payload_rejects_unexpected_hook_key():
    response = hooks_list_response(hook("bad-key", "herdr"))

    with pytest.raises(RuntimeError, match="unexpected Codex hook key"):
        generate_herdr_hook_state.build_payload(
            response,
            hook_command="herdr",
            hooks_json_path="/home/me/.codex/hooks.json",
        )
