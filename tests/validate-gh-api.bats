#!/usr/bin/env bats
# validate-gh-api.sh (Claude Code PreToolUse フック) の検査ロジックのテスト。
# exit 0 = 許可 / exit 2 = ブロック。

setup() {
  REPO_ROOT="$(git rev-parse --show-toplevel)"
  HOOK="$REPO_ROOT/claude/hooks/validate-gh-api.sh"
}

# command 文字列を tool_input JSON に包んでフックへ流す
run_hook() {
  local cmd=$1
  run bash -c 'jq -n --arg c "$1" "{tool_input: {command: \$c}}" | bash "$2"' _ "$cmd" "$HOOK"
}

@test "non-gh command is allowed" {
  run_hook "ls -la"
  [ "$status" -eq 0 ]
}

@test "gh pr list is allowed (not api-get)" {
  run_hook "gh pr list --limit 10"
  [ "$status" -eq 0 ]
}

@test "plain gh api-get is allowed" {
  run_hook "gh api-get repos/owner/repo/pulls"
  [ "$status" -eq 0 ]
}

@test "gh api-get with -F field is allowed" {
  run_hook "gh api-get repos/owner/repo/issues -F state=open"
  [ "$status" -eq 0 ]
}

@test "bare -- mid-command is blocked" {
  run_hook "gh api-get repos/o/r -- --method DELETE"
  [ "$status" -eq 2 ]
}

@test "trailing -- is blocked" {
  run_hook "gh api-get repos/o/r --"
  [ "$status" -eq 2 ]
}

@test "--method DELETE is blocked" {
  run_hook "gh api-get repos/o/r --method DELETE"
  [ "$status" -eq 2 ]
}

@test "--method=DELETE is blocked" {
  run_hook "gh api-get repos/o/r --method=DELETE"
  [ "$status" -eq 2 ]
}

@test "trailing --method is blocked" {
  run_hook "gh api-get repos/o/r --method"
  [ "$status" -eq 2 ]
}

@test "-X DELETE is blocked" {
  run_hook "gh api-get repos/o/r -X DELETE"
  [ "$status" -eq 2 ]
}

@test "-XDELETE (attached form) is blocked" {
  run_hook "gh api-get repos/o/r -XDELETE"
  [ "$status" -eq 2 ]
}

@test "empty tool_input is allowed" {
  run bash -c 'echo "{}" | bash "$1"' _ "$HOOK"
  [ "$status" -eq 0 ]
}
