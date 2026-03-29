#!/usr/bin/env bash
set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# gh api-get 以外はスキップ
if [[ ! "$COMMAND" =~ ^gh[[:space:]]+api-get ]]; then
  exit 0
fi

# -- (フラグ終端記号) の検出: alias の --method GET 強制をバイパスする試み
if [[ "$COMMAND" =~ [[:space:]]--([[:space:]]|$) ]]; then
  echo "Blocked: '--' is not allowed in gh api-get commands" >&2
  exit 2
fi

exit 0
