#!/usr/bin/env bats
# update-pins の git-wt vendorHash 経路を fake repo とスタブだけで検査する。

setup() {
  REPO_ROOT="$(git rev-parse --show-toplevel)"
  WORK="$(mktemp -d)"
  mkdir -p "$WORK/nix/apps" "$WORK/nix/pins"
  cp "$REPO_ROOT/nix/apps/update-pins.sh" "$WORK/nix/apps/update-pins.sh"
  cp "$REPO_ROOT"/nix/pins/*.json "$WORK/nix/pins/"

  STUB_DIR="$WORK/stub"
  mkdir -p "$STUB_DIR"
  export UPDATE_PINS_FAKE_ROOT="$WORK"
  export UPDATE_PINS_NIX_BUILD_COUNT="$WORK/nix-build-count"

  cat >"$STUB_DIR/git" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail

if [ "$1" = "rev-parse" ] && [ "${2:-}" = "--show-toplevel" ]; then
  printf '%s\n' "$UPDATE_PINS_FAKE_ROOT"
  exit 0
fi

if [ "$1" = "diff" ] && [ "${2:-}" = "--quiet" ]; then
  exit "${GIT_DIFF_STATUS:-1}"
fi

echo "unexpected git invocation: $*" >&2
exit 1
EOS

  cat >"$STUB_DIR/gh" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail

case "$*" in
"api repos/aannoo/hcom/releases/latest --jq .tag_name")
  printf 'v%s\n' "$(jq -r .version "$UPDATE_PINS_FAKE_ROOT/nix/pins/hcom.json")"
  ;;
"api repos/stablyai/agent-slack/releases/latest --jq .tag_name")
  printf 'v%s\n' "$(jq -r .version "$UPDATE_PINS_FAKE_ROOT/nix/pins/agent-slack.json")"
  ;;
"api repos/k1LoW/git-wt/releases/latest --jq .tag_name")
  printf 'v999.0.0\n'
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
  elif [[ "$*" == *"config-schema.json"* ]]; then
    printf '{"hash":"%s"}\n' "$(jq -r .hash "$UPDATE_PINS_FAKE_ROOT/nix/pins/codex-schema.json")"
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
  exit 0
fi

echo "unexpected nix invocation: $*" >&2
exit 1
EOS

  chmod +x "$STUB_DIR/git" "$STUB_DIR/gh" "$STUB_DIR/nix"
  export PATH="$STUB_DIR:$PATH"
}

teardown() {
  rm -rf "$WORK"
}

run_update_pins() {
  run bash -eu -o pipefail "$WORK/nix/apps/update-pins.sh"
}

@test "git-wt pin is restored when vendorHash cannot be extracted" {
  original="$WORK/original-git-wt.json"
  cp "$WORK/nix/pins/git-wt.json" "$original"
  export UPDATE_PINS_BUILD_MODE=no-hash

  run_update_pins

  [ "$status" -ne 0 ]
  cmp -s "$WORK/nix/pins/git-wt.json" "$original"
}

@test "git-wt pin is updated after vendorHash extraction and verification" {
  export UPDATE_PINS_BUILD_MODE=success

  run_update_pins

  [ "$status" -eq 0 ]
  [ "$(jq -r .version "$WORK/nix/pins/git-wt.json")" = "999.0.0" ]
  [ "$(jq -r .srcHash "$WORK/nix/pins/git-wt.json")" = "sha256-src-for-test" ]
  [ "$(jq -r .vendorHash "$WORK/nix/pins/git-wt.json")" = "sha256-vendor-for-test" ]
}

@test "git-wt pin is restored when verification build fails" {
  original="$WORK/original-git-wt.json"
  cp "$WORK/nix/pins/git-wt.json" "$original"
  export UPDATE_PINS_BUILD_MODE=verify-fails

  run_update_pins

  [ "$status" -ne 0 ]
  cmp -s "$WORK/nix/pins/git-wt.json" "$original"
}
