#!/usr/bin/env bash
set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# gh api-get 以外はスキップ
if [[ ! $COMMAND =~ ^gh[[:space:]]+api-get ]]; then
  exit 0
fi

# -- (フラグ終端記号) の検出: alias の --method GET 強制をバイパスする試み
if [[ $COMMAND =~ [[:space:]]--([[:space:]]|$) ]]; then
  echo "Blocked: '--' is not allowed in gh api-get commands" >&2
  exit 2
fi

# --method / -X の明示指定の検出: alias 末尾の --method GET が勝つのは
# gh (pflag) の「後勝ち」という実装詳細に過ぎないため、上書きの試み自体を
# 拒否する。-XDELETE のような結合形も [[:space:]]-X で捕捉する。
if [[ $COMMAND =~ [[:space:]]-X ]] || [[ $COMMAND =~ [[:space:]]--method([[:space:]=]|$) ]]; then
  echo "Blocked: explicit --method/-X is not allowed in gh api-get commands" >&2
  exit 2
fi

exit 0
