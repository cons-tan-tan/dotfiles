#!/usr/bin/env python3
"""TOML を非破壊で deep-merge し、候補ファイルに書き出す汎用ツール。

merge 対象 (テーブル/キー/値) は呼び出し側が payload で渡す。tool 固有の知識を
ここに持たせないための分離。tomlkit を選ぶのは、コロンを含むキー
(例 "...:pre_tool_use:0:0") とコメントを両方保持するため
(dasel はコロンキーで破綻し、tomllib+tomli_w はコメントを失う)。

本番を直接置き換えず <output> (候補) に書く。呼び出し側が検証してから本番へ
mv することで、検証を通った設定だけが本番に置かれる (置換の原子性は呼び出し側)。

Usage: merge.py <source.toml> <payload.json> <output.toml>
"""
from collections.abc import MutableMapping
import json
import os
import sys

import tomlkit

source_path, payload_path, output_path = sys.argv[1], sys.argv[2], sys.argv[3]

with open(payload_path, encoding="utf-8") as f:
    payload = json.load(f)

source_exists = os.path.exists(source_path)
if source_exists:
    with open(source_path, encoding="utf-8") as f:
        doc = tomlkit.parse(f.read())
else:
    doc = tomlkit.document()


def deep_merge(dst, src):
    for key, val in src.items():
        # payload に無いキーは触らない — 既存の動的な書き込みを保全するため。
        if isinstance(val, dict):
            if not isinstance(dst.get(key), MutableMapping):
                dst[key] = tomlkit.table()
            deep_merge(dst[key], val)
        else:
            dst[key] = val


deep_merge(doc, payload)

os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)
with open(output_path, "w", encoding="utf-8") as f:
    f.write(tomlkit.dumps(doc))

# config には project trust 等の機密が入るため mv 後に権限を緩めない。open 任せ
# だと umask 依存 (例 0644) で緩むので、権限を明示的に設定する。
os.chmod(output_path, (os.stat(source_path).st_mode & 0o7777) if source_exists else 0o600)
