#!/usr/bin/env bash
set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# gh api-get を含まないコマンドはスキップ。行頭アンカーだと env 前置
# (FOO=1 gh api-get) やコマンド連結 (true && gh api-get) でフックごと
# バイパスされるため、単語境界付きでコマンド全体を走査する。
if [[ ! $COMMAND =~ (^|[^[:alnum:]_-])gh[[:space:]]+api-get ]]; then
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
