#!/usr/bin/env bats
# update-pins の全体 transaction を fake repo とスタブだけで検査する。

setup() {
  REPO_ROOT="$(git rev-parse --show-toplevel)"
  WORK="$(mktemp -d)"
  mkdir -p "$WORK/nix/apps" "$WORK/nix/pins"
  cp "$REPO_ROOT/nix/apps/update-pins.sh" "$WORK/nix/apps/update-pins.sh"
  cp "$REPO_ROOT"/nix/pins/*.json "$WORK/nix/pins/"
  cp "$REPO_ROOT/flake.lock" "$WORK/flake.lock"

  (
    cd "$WORK"
    git init -q
    git config user.email update-pins-test@example.invalid
    git config user.name "update-pins test"
    git add flake.lock nix/apps/update-pins.sh nix/pins/*.json
    git commit -q -m "initial managed files"
  )

  STUB_DIR="$WORK/stub"
  mkdir -p "$STUB_DIR"
  export UPDATE_PINS_FAKE_ROOT="$WORK"
  export UPDATE_PINS_NIX_BUILD_COUNT="$WORK/nix-build-count"

  cat >"$STUB_DIR/gh" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail

case "$*" in
"api repos/aannoo/hcom/releases/latest --jq .tag_name")
  printf '%s\n' "${UPDATE_PINS_HCOM_TAG:-v$(jq -r .version "$UPDATE_PINS_FAKE_ROOT/nix/pins/hcom.json")}"
  ;;
"api repos/stablyai/agent-slack/releases/latest --jq .tag_name")
  printf '%s\n' "${UPDATE_PINS_AGENT_SLACK_TAG:-v$(jq -r .version "$UPDATE_PINS_FAKE_ROOT/nix/pins/agent-slack.json")}"
  ;;
"api repos/k1LoW/git-wt/releases/latest --jq .tag_name")
  printf '%s\n' "${UPDATE_PINS_GIT_WT_TAG:-v999.0.0}"
  ;;
*)
  echo "unexpected gh invocation: $*" >&2
  exit 1
  ;;
esac
EOS

  cat >"$STUB_DIR/nix" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail

if [ "$1" = "store" ] && [ "${2:-}" = "prefetch-file" ]; then
  if [[ " $* " == *" --unpack "* ]]; then
    printf '{"hash":"sha256-src-for-test"}\n'
  else
    printf '{"hash":"sha256-asset-for-test"}\n'
  fi
  exit 0
fi

if [ "$1" = "build" ] && [ "${2:-}" = ".#git-wt" ] && [ "${3:-}" = "--no-link" ]; then
  count=0
  if [ -f "$UPDATE_PINS_NIX_BUILD_COUNT" ]; then
    count=$(cat "$UPDATE_PINS_NIX_BUILD_COUNT")
  fi
  count=$((count + 1))
  printf '%s\n' "$count" >"$UPDATE_PINS_NIX_BUILD_COUNT"

  case "${UPDATE_PINS_BUILD_MODE:-}" in
  no-hash)
    echo "builder failed before printing a hash" >&2
    exit 1
    ;;
  success)
    if [ "$count" -eq 1 ]; then
      echo "error: hash mismatch"
      echo "got: sha256-vendor-for-test"
      exit 1
    fi
    exit 0
    ;;
  verify-fails)
    if [ "$count" -eq 1 ]; then
      echo "error: hash mismatch"
      echo "got: sha256-vendor-for-test"
      exit 1
    fi
    echo "verification build failed" >&2
    exit 1
    ;;
  *)
    echo "UPDATE_PINS_BUILD_MODE is not set" >&2
    exit 1
    ;;
  esac
fi

if [ "$1" = "flake" ] && [ "${2:-}" = "update" ]; then
  input=${3:-}
  printf '{"updated":"%s"}\n' "$input" >"$UPDATE_PINS_FAKE_ROOT/flake.lock"
  if [ "${UPDATE_PINS_FAIL_FLAKE_UPDATE:-}" = "$input" ]; then
    echo "flake update failed for $input" >&2
    exit 1
  fi
  exit 0
fi

echo "unexpected nix invocation: $*" >&2
exit 1
EOS

  chmod +x "$STUB_DIR/gh" "$STUB_DIR/nix"
  export PATH="$STUB_DIR:$PATH"
}

teardown() {
  rm -rf "$WORK"
}

run_update_pins() {
  run bash -eu -o pipefail -c 'cd "$UPDATE_PINS_FAKE_ROOT"; bash -eu -o pipefail nix/apps/update-pins.sh 2>&1'
}

save_managed() {
  local dst=$1
  mkdir -p "$dst/nix/pins"
  cp "$WORK/flake.lock" "$dst/flake.lock"
  cp "$WORK"/nix/pins/*.json "$dst/nix/pins/"
}

assert_managed_matches() {
  local expected=$1 pin name
  cmp -s "$WORK/flake.lock" "$expected/flake.lock" || return 1
  for pin in "$expected"/nix/pins/*.json; do
    name=$(basename "$pin")
    cmp -s "$WORK/nix/pins/$name" "$pin" || return 1
  done
}

@test "managed dirty files are rejected without changing contents" {
  printf '{"dirty":true}\n' >"$WORK/nix/pins/hcom.json"
  original="$WORK/original"
  save_managed "$original"

  run_update_pins

  [ "$status" -ne 0 ]
  assert_managed_matches "$original"
}

@test "managed staged dirty files are rejected without changing contents" {
  printf '{"dirty":true}\n' >"$WORK/nix/pins/hcom.json"
  original="$WORK/original"
  save_managed "$original"
  git -C "$WORK" add nix/pins/hcom.json

  run_update_pins

  [ "$status" -ne 0 ]
  assert_managed_matches "$original"
}

@test "deleted tracked pin is rejected as managed dirty" {
  original="$WORK/original"
  save_managed "$original"
  rm "$WORK/nix/pins/hcom.json"

  run_update_pins

  [ "$status" -ne 0 ]
  [[ "$output" == *"managed files already have unstaged changes"* ]]
  [ ! -e "$WORK/nix/pins/hcom.json" ]
}

@test "hcom flake update failure restores hcom pin and flake.lock" {
  original="$WORK/original"
  save_managed "$original"
  export UPDATE_PINS_HCOM_TAG=v1.2.3
  export UPDATE_PINS_FAIL_FLAKE_UPDATE=hcom-src

  run_update_pins

  [ "$status" -ne 0 ]
  assert_managed_matches "$original"
}

@test "agent-slack flake update failure restores earlier pin changes" {
  original="$WORK/original"
  save_managed "$original"
  export UPDATE_PINS_HCOM_TAG=v1.2.3
  export UPDATE_PINS_AGENT_SLACK_TAG=v4.5.6
  export UPDATE_PINS_FAIL_FLAKE_UPDATE=agent-slack-skill

  run_update_pins

  [ "$status" -ne 0 ]
  assert_managed_matches "$original"
}

@test "git-wt vendorHash extraction failure restores all managed files" {
  original="$WORK/original"
  save_managed "$original"
  export UPDATE_PINS_HCOM_TAG=v1.2.3
  export UPDATE_PINS_AGENT_SLACK_TAG=v4.5.6
  export UPDATE_PINS_BUILD_MODE=no-hash

  run_update_pins

  [ "$status" -ne 0 ]
  assert_managed_matches "$original"
}

@test "git-wt verification build failure restores all managed files" {
  original="$WORK/original"
  save_managed "$original"
  export UPDATE_PINS_HCOM_TAG=v1.2.3
  export UPDATE_PINS_AGENT_SLACK_TAG=v4.5.6
  export UPDATE_PINS_BUILD_MODE=verify-fails

  run_update_pins

  [ "$status" -ne 0 ]
  assert_managed_matches "$original"
}

@test "successful update leaves expected managed file changes" {
  original="$WORK/original"
  save_managed "$original"
  export UPDATE_PINS_HCOM_TAG=v1.2.3
  export UPDATE_PINS_AGENT_SLACK_TAG=v4.5.6
  export UPDATE_PINS_BUILD_MODE=success

  run_update_pins

  [ "$status" -eq 0 ]
  [ "$(jq -r .version "$WORK/nix/pins/hcom.json")" = "1.2.3" ]
  [ "$(jq -r '.assets["aarch64-darwin"].hash' "$WORK/nix/pins/hcom.json")" = "sha256-asset-for-test" ]
  [ "$(jq -r .version "$WORK/nix/pins/agent-slack.json")" = "4.5.6" ]
  [ "$(jq -r .version "$WORK/nix/pins/git-wt.json")" = "999.0.0" ]
  [ "$(jq -r .srcHash "$WORK/nix/pins/git-wt.json")" = "sha256-src-for-test" ]
  [ "$(jq -r .vendorHash "$WORK/nix/pins/git-wt.json")" = "sha256-vendor-for-test" ]
  [ "$(jq -r .updated "$WORK/flake.lock")" = "agent-slack-skill" ]
  ! assert_managed_matches "$original"
}
