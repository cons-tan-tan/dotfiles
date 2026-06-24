"""merge.py の deep-merge と権限複製のテスト。

merge.py は argv を取るスクリプトなので subprocess で実行する (import すると
即座に argv を読んで落ちるため)。
"""

import json
import os
import pathlib
import subprocess
import sys

MERGE = pathlib.Path(__file__).parent / "merge.py"


def run_merge(tmp_path, source_text, payload, *, source_mode=None):
    src = tmp_path / "source.toml"
    pay = tmp_path / "payload.json"
    out = tmp_path / "out" / "output.toml"
    if source_text is not None:
        src.write_text(source_text, encoding="utf-8")
        if source_mode is not None:
            os.chmod(src, source_mode)
    pay.write_text(json.dumps(payload), encoding="utf-8")
    subprocess.run(
        [sys.executable, str(MERGE), str(src), str(pay), str(out)],
        check=True,
    )
    return out


def test_new_file_gets_0600(tmp_path):
    out = run_merge(tmp_path, None, {"a": {"b": 1}})
    assert (os.stat(out).st_mode & 0o7777) == 0o600
    assert "b = 1" in out.read_text(encoding="utf-8")


def test_existing_mode_is_replicated(tmp_path):
    out = run_merge(tmp_path, "x = 1\n", {"y": 2}, source_mode=0o644)
    assert (os.stat(out).st_mode & 0o7777) == 0o644


def test_deep_merge_preserves_untouched_keys(tmp_path):
    source = '# comment kept\n[tool]\nkeep = "yes"\n[tool.sub]\nold = 1\n'
    out = run_merge(tmp_path, source, {"tool": {"sub": {"new": 2}}})
    text = out.read_text(encoding="utf-8")
    assert 'keep = "yes"' in text
    assert "old = 1" in text
    assert "new = 2" in text
    assert "# comment kept" in text  # tomlkit を選んだ理由そのもの


def test_scalar_overwrites_table(tmp_path):
    out = run_merge(tmp_path, "[a]\nx = 1\n", {"a": "flat"})
    assert 'a = "flat"' in out.read_text(encoding="utf-8")


def test_delete_paths_remove_only_requested_tables(tmp_path):
    source = """
[plugins."keep@source"]
enabled = true

[plugins."herdr@herdr"]
enabled = false

[marketplaces.herdr]
source = "old"
"""
    payload = {
        "__delete": [
            ["plugins", "herdr@herdr"],
            ["marketplaces", "herdr"],
        ],
        "plugins": {"new@source": {"enabled": True}},
    }
    out = run_merge(tmp_path, source, payload)
    text = out.read_text(encoding="utf-8")
    assert "herdr@herdr" not in text
    assert "marketplaces.herdr" not in text
    assert "keep@source" in text
    assert "new@source" in text
