#!/usr/bin/env bats
# update-pins の全体 transaction を fake repo とスタブだけで検査する。

make_difit_tarball() {
  local version=$1
  mkdir -p "$WORK/difit-tar/package"
  printf '{"name":"difit","version":"%s"}\n' "$version" >"$WORK/difit-tar/package/package.json"
  tar -czf "$WORK/difit.tgz" -C "$WORK/difit-tar" package
  export UPDATE_PINS_DIFIT_TARBALL="$WORK/difit.tgz"
}

setup() {
  REPO_ROOT="$(git rev-parse --show-toplevel)"
  BASH_BIN="$(command -v bash)"
  WORK="$(mktemp -d)"
  mkdir -p "$WORK/nix/apps" "$WORK/nix/pins" "$WORK/nix/packages/difit"
  cp "$REPO_ROOT/nix/apps/update-pins.sh" "$WORK/nix/apps/update-pins.sh"
  cp "$REPO_ROOT"/nix/pins/*.json "$WORK/nix/pins/"
  cp "$REPO_ROOT/nix/packages/difit/package-lock.json" "$WORK/nix/packages/difit/package-lock.json"
  cp "$REPO_ROOT/flake.nix" "$WORK/flake.nix"
  cp "$REPO_ROOT/flake.lock" "$WORK/flake.lock"

  (
    cd "$WORK"
    git init -q
    git config user.email update-pins-test@example.invalid
    git config user.name "update-pins test"
    git config commit.gpgsign false
    git add flake.nix flake.lock nix/apps/update-pins.sh nix/packages/difit/package-lock.json nix/pins/*.json
    git commit -q -m "initial managed files"
  )

  STUB_DIR="$WORK/stub"
  mkdir -p "$STUB_DIR"
  export UPDATE_PINS_FAKE_ROOT="$WORK"
  export UPDATE_PINS_SHELLFIRM_BUILD_COUNT="$WORK/shellfirm-build-count"
  export UPDATE_PINS_DIFIT_BUILD_COUNT="$WORK/difit-build-count"
  export UPDATE_PINS_FLAKE_UPDATE_LOG="$WORK/flake-update.log"
  export UPDATE_PINS_COMMAND_LOG="$WORK/command.log"

  if [ -z "${UPDATE_PINS_TEST_BIN:-}" ]; then
    UPDATE_PINS_TEST_BIN="$WORK/update-pins-under-test"
    printf '#!%s\n' "$BASH_BIN" >"$UPDATE_PINS_TEST_BIN"
    printf 'set -euo pipefail\nexec "%s" -eu -o pipefail "$UPDATE_PINS_FAKE_ROOT/nix/apps/update-pins.sh" "$@"\n' "$BASH_BIN" >>"$UPDATE_PINS_TEST_BIN"
    chmod +x "$UPDATE_PINS_TEST_BIN"
  fi
  case "$UPDATE_PINS_TEST_BIN" in
  /*) ;;
  *)
    echo "UPDATE_PINS_TEST_BIN must be an absolute path" >&2
    return 1
    ;;
  esac
  if [ ! -x "$UPDATE_PINS_TEST_BIN" ]; then
    echo "UPDATE_PINS_TEST_BIN is not executable: $UPDATE_PINS_TEST_BIN" >&2
    return 1
  fi
  export UPDATE_PINS_TEST_BIN

  make_difit_tarball "$(sed -n 's|.*github:yoshiko-pg/difit/v\\([^"]*\\)";|\\1|p' "$WORK/flake.nix")"

  printf '#!%s\n' "$BASH_BIN" >"$STUB_DIR/gh"
  cat >>"$STUB_DIR/gh" <<'EOS'
set -euo pipefail

{
  printf 'gh'
  printf ' %q' "$@"
  printf '\n'
} >>"$UPDATE_PINS_COMMAND_LOG"

flake_version() {
  local repo=$1
  sed -n "s|.*github:$repo/v\\([^\"]*\\)\";|\\1|p" "$UPDATE_PINS_FAKE_ROOT/flake.nix"
}

case "$*" in
"api repos/aannoo/hcom/releases/latest --jq .tag_name")
  printf '%s\n' "${UPDATE_PINS_HCOM_TAG:-v$(flake_version aannoo/hcom)}"
  ;;
"api repos/stablyai/agent-slack/releases/latest --jq .tag_name")
  printf '%s\n' "${UPDATE_PINS_AGENT_SLACK_TAG:-v$(flake_version stablyai/agent-slack)}"
  ;;
"api repos/vercel-labs/agent-browser/releases/latest --jq .tag_name")
  printf '%s\n' "${UPDATE_PINS_AGENT_BROWSER_TAG:-v$(flake_version vercel-labs/agent-browser)}"
  ;;
"api repos/watchexec/watchexec/releases/latest --jq .tag_name")
  printf '%s\n' "${UPDATE_PINS_WATCHEXEC_TAG:-v$(jq -r .version "$UPDATE_PINS_FAKE_ROOT/nix/pins/watchexec.json")}"
  ;;
"api repos/kaplanelad/shellfirm/releases/latest --jq .tag_name")
  printf '%s\n' "${UPDATE_PINS_SHELLFIRM_TAG:-v$(jq -r .version "$UPDATE_PINS_FAKE_ROOT/nix/pins/shellfirm.json")}"
  ;;
"api repos/ogulcancelik/herdr/releases/latest --jq .tag_name")
  printf '%s\n' "${UPDATE_PINS_HERDR_TAG:-v$(jq -r .version "$UPDATE_PINS_FAKE_ROOT/nix/pins/herdr.json")}"
  ;;
*)
  echo "unexpected gh invocation: $*" >&2
  exit 1
  ;;
esac
EOS

  printf '#!%s\n' "$BASH_BIN" >"$STUB_DIR/curl"
  cat >>"$STUB_DIR/curl" <<'EOS'
set -euo pipefail

{
  printf 'curl'
  printf ' %q' "$@"
  printf '\n'
} >>"$UPDATE_PINS_COMMAND_LOG"

flake_version() {
  local repo=$1
  sed -n "s|.*github:$repo/v\\([^\"]*\\)\";|\\1|p" "$UPDATE_PINS_FAKE_ROOT/flake.nix"
}

if [ "$1" != "-fsSL" ]; then
  echo "unexpected curl invocation: $*" >&2
  exit 1
fi

case "${2:-}" in
https://registry.npmjs.org/difit/latest)
  printf '{"version":"%s"}\n' "${UPDATE_PINS_DIFIT_VERSION:-$(flake_version yoshiko-pg/difit)}"
  ;;
https://registry.npmjs.org/difit/-/difit-*.tgz)
  cat "$UPDATE_PINS_DIFIT_TARBALL"
  ;;
https://persistent.oaistatic.com/codex-app-prod/appcast.xml)
  version=${UPDATE_PINS_CODEX_APP_VERSION:-$(jq -r .version "$UPDATE_PINS_FAKE_ROOT/nix/pins/codex-app.json")}
  url=${UPDATE_PINS_CODEX_APP_URL:-$(jq -r .url "$UPDATE_PINS_FAKE_ROOT/nix/pins/codex-app.json")}
  cat <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
  <channel>
    <item>
      <title>$version</title>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>
      <enclosure url="$url" length="123" type="application/octet-stream" />
    </item>
  </channel>
</rss>
XML
  ;;
*)
  echo "unexpected curl invocation: $*" >&2
  exit 1
  ;;
esac
EOS

  printf '#!%s\n' "$BASH_BIN" >"$STUB_DIR/npm"
  cat >>"$STUB_DIR/npm" <<'EOS'
set -euo pipefail

{
  printf 'npm'
  printf ' %q' "$@"
  printf '\n'
  printf 'npm-cwd %q\n' "$PWD"
} >>"$UPDATE_PINS_COMMAND_LOG"

if [ "$#" -eq 5 ] \
  && [ "$1" = "install" ] \
  && [ "$2" = "--package-lock-only" ] \
  && [ "$3" = "--ignore-scripts" ] \
  && [ "$4" = "--no-audit" ] \
  && [ "$5" = "--no-fund" ]; then
  cat >package-lock.json <<JSON
{
  "name": "difit",
  "version": "${UPDATE_PINS_DIFIT_VERSION:-0.0.0}",
  "lockfileVersion": 3,
  "packages": {
    "": {
      "name": "difit",
      "version": "${UPDATE_PINS_DIFIT_VERSION:-0.0.0}"
    }
  }
}
JSON
  exit 0
fi

echo "unexpected npm invocation: $*" >&2
exit 1
EOS

  printf '#!%s\n' "$BASH_BIN" >"$STUB_DIR/nix"
  cat >>"$STUB_DIR/nix" <<'EOS'
set -euo pipefail

{
  printf 'nix'
  printf ' %q' "$@"
  printf '\n'
} >>"$UPDATE_PINS_COMMAND_LOG"

if [ "$1" = "store" ] && [ "${2:-}" = "prefetch-file" ]; then
  if [[ " $* " == *"github.com/ogulcancelik/herdr/archive/refs/tags/"* ]] && [ "${UPDATE_PINS_FAIL_HERDR_PREFETCH:-}" = "source" ]; then
    echo "herdr source prefetch failed" >&2
    exit 1
  fi
  if [[ " $* " == *"github.com/watchexec/watchexec/releases/download/"* ]] && [ -n "${UPDATE_PINS_FAIL_WATCHEXEC_TARGET:-}" ] && [[ " $* " == *"$UPDATE_PINS_FAIL_WATCHEXEC_TARGET"* ]]; then
    echo "watchexec asset prefetch failed for $UPDATE_PINS_FAIL_WATCHEXEC_TARGET" >&2
    exit 1
  fi
  if [[ " $* " == *"persistent.oaistatic.com/codex-app-prod/"*".zip"* ]]; then
    zip_path="$UPDATE_PINS_FAKE_ROOT/codex-app.zip"
    app_name=${UPDATE_PINS_CODEX_APP_NAME:-$(jq -r .appName "$UPDATE_PINS_FAKE_ROOT/nix/pins/codex-app.json")}
    bundle_identifier=${UPDATE_PINS_CODEX_APP_BUNDLE_IDENTIFIER:-$(jq -r .bundleIdentifier "$UPDATE_PINS_FAKE_ROOT/nix/pins/codex-app.json")}
    display_name=${UPDATE_PINS_CODEX_APP_DISPLAY_NAME:-$(jq -r .displayName "$UPDATE_PINS_FAKE_ROOT/nix/pins/codex-app.json")}
    version=${UPDATE_PINS_CODEX_APP_BUNDLE_VERSION:-${UPDATE_PINS_CODEX_APP_VERSION:-$(jq -r .version "$UPDATE_PINS_FAKE_ROOT/nix/pins/codex-app.json")}}
    python3 - "$zip_path" "$app_name" "$bundle_identifier" "$display_name" "$version" <<'PY'
import plistlib
import sys
import zipfile

zip_path, app_name, bundle_identifier, display_name, version = sys.argv[1:]
plist = {
    "CFBundleDisplayName": display_name,
    "CFBundleIdentifier": bundle_identifier,
    "CFBundleName": display_name,
    "CFBundleShortVersionString": version,
}

with zipfile.ZipFile(zip_path, "w") as archive:
    archive.writestr(f"{app_name}/Contents/Info.plist", plistlib.dumps(plist))
PY
    printf '{"hash":"sha256-codex-app-for-test","storePath":"%s"}\n' "$zip_path"
    exit 0
  fi
  if [ "${3:-}" = "--json" ] && [ "${4:-}" = "https://json.schemastore.org/claude-code-settings.json" ]; then
    printf '{"hash":"%s"}\n' "${UPDATE_PINS_SCHEMA_HASH:-sha256-schema-for-test}"
    exit 0
  fi
  if [[ " $* " == *"registry.npmjs.org/difit/-/difit-"* ]]; then
    printf '{"hash":"sha256-difit-src-for-test","storePath":"%s"}\n' "$UPDATE_PINS_DIFIT_TARBALL"
    exit 0
  fi
  if [[ " $* " == *" --unpack "* ]]; then
    printf '{"hash":"sha256-src-for-test"}\n'
  else
    printf '{"hash":"sha256-asset-for-test"}\n'
  fi
  exit 0
fi

if [ "$1" = "build" ] && [ "${2:-}" = "--impure" ] && [ "${3:-}" = "--expr" ] && [[ "${4:-}" != *'pkgs.dotfilesPackages.${builtins.getEnv "UPDATE_PINS_PACKAGE"}'* ]]; then
  echo "local package build did not use pkgs.dotfilesPackages" >&2
  exit 1
fi

if [ "$1" = "build" ] && [ "${2:-}" = "--impure" ] && [ "${3:-}" = "--expr" ] && [ "${5:-}" = "--no-link" ] && [ "${UPDATE_PINS_PACKAGE:-}" = "shellfirm" ]; then
  count=0
  if [ -f "$UPDATE_PINS_SHELLFIRM_BUILD_COUNT" ]; then
    count=$(cat "$UPDATE_PINS_SHELLFIRM_BUILD_COUNT")
  fi
  count=$((count + 1))
  printf '%s\n' "$count" >"$UPDATE_PINS_SHELLFIRM_BUILD_COUNT"

  case "${UPDATE_PINS_SHELLFIRM_BUILD_MODE:-}" in
  no-hash)
    echo "builder failed before printing a hash" >&2
    exit 1
    ;;
  success)
    if [ "$count" -eq 1 ]; then
      echo "error: hash mismatch" >&2
      echo "got: sha256-cargo-for-test" >&2
      exit 1
    fi
    exit 0
    ;;
  verify-fails)
    if [ "$count" -eq 1 ]; then
      echo "error: hash mismatch" >&2
      echo "got: sha256-cargo-for-test" >&2
      exit 1
    fi
    echo "verification build failed" >&2
    exit 1
    ;;
  *)
    echo "UPDATE_PINS_SHELLFIRM_BUILD_MODE is not set" >&2
    exit 1
    ;;
  esac
fi

if [ "$1" = "build" ] && [ "${2:-}" = "--impure" ] && [ "${3:-}" = "--expr" ] && [ "${5:-}" = "--no-link" ] && [ "${UPDATE_PINS_PACKAGE:-}" = "difit" ]; then
  count=0
  if [ -f "$UPDATE_PINS_DIFIT_BUILD_COUNT" ]; then
    count=$(cat "$UPDATE_PINS_DIFIT_BUILD_COUNT")
  fi
  count=$((count + 1))
  printf '%s\n' "$count" >"$UPDATE_PINS_DIFIT_BUILD_COUNT"

  case "${UPDATE_PINS_DIFIT_BUILD_MODE:-}" in
  no-hash)
    echo "builder failed before printing a hash" >&2
    exit 1
    ;;
  success)
    if [ "$count" -eq 1 ]; then
      echo "error: hash mismatch" >&2
      echo "got: sha256-npmdeps-for-test" >&2
      exit 1
    fi
    exit 0
    ;;
  verify-fails)
    if [ "$count" -eq 1 ]; then
      echo "error: hash mismatch" >&2
      echo "got: sha256-npmdeps-for-test" >&2
      exit 1
    fi
    echo "verification build failed" >&2
    exit 1
    ;;
  *)
    echo "UPDATE_PINS_DIFIT_BUILD_MODE is not set" >&2
    exit 1
    ;;
  esac
fi

if [ "$1" = "flake" ] && [ "${2:-}" = "update" ]; then
  input=${3:-}
  printf '%s\n' "$input" >>"$UPDATE_PINS_FLAKE_UPDATE_LOG"
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

  chmod +x "$STUB_DIR/gh" "$STUB_DIR/curl" "$STUB_DIR/npm" "$STUB_DIR/nix"
  export PATH="$STUB_DIR:$PATH"
}

teardown() {
  rm -rf "$WORK"
}

run_update_pins() {
  run bash -eu -o pipefail -c 'cd "$UPDATE_PINS_FAKE_ROOT"; exec "$UPDATE_PINS_TEST_BIN" "$@" 2>&1' update-pins-test "$@"
}

save_managed() {
  local dst=$1
  mkdir -p "$dst/nix/pins" "$dst/nix/packages/difit"
  cp -p "$WORK/flake.nix" "$dst/flake.nix"
  cp -p "$WORK/flake.lock" "$dst/flake.lock"
  cp -p "$WORK"/nix/pins/*.json "$dst/nix/pins/"
  cp -p "$WORK/nix/packages/difit/package-lock.json" "$dst/nix/packages/difit/package-lock.json"
}

assert_managed_matches() {
  local expected=$1 pin name
  cmp -s "$WORK/flake.nix" "$expected/flake.nix" || return 1
  assert_same_mode "$WORK/flake.nix" "$expected/flake.nix" || return 1
  cmp -s "$WORK/flake.lock" "$expected/flake.lock" || return 1
  assert_same_mode "$WORK/flake.lock" "$expected/flake.lock" || return 1
  cmp -s "$WORK/nix/packages/difit/package-lock.json" "$expected/nix/packages/difit/package-lock.json" || return 1
  assert_same_mode "$WORK/nix/packages/difit/package-lock.json" "$expected/nix/packages/difit/package-lock.json" || return 1
  for pin in "$expected"/nix/pins/*.json; do
    name=$(basename "$pin")
    cmp -s "$WORK/nix/pins/$name" "$pin" || return 1
    assert_same_mode "$WORK/nix/pins/$name" "$pin" || return 1
  done
}

assert_same_mode() {
  python3 - "$1" "$2" <<'PY'
import os
import stat
import sys

actual, expected = sys.argv[1:]
if stat.S_IMODE(os.stat(actual).st_mode) != stat.S_IMODE(os.stat(expected).st_mode):
    raise SystemExit(1)
PY
}

assert_no_staging_files() {
  local leftover
  leftover=$(find "$WORK" -name '*.update-pins*' -print -quit)
  [ -z "$leftover" ]
}

paired_version() {
  local repo=$1 file=${2:-"$WORK/flake.nix"}
  sed -n "s|.*github:$repo/v\\([^\"]*\\)\";|\\1|p" "$file"
}

make_unrelated_updates_noop() {
  export UPDATE_PINS_AGENT_BROWSER_TAG="v$(paired_version vercel-labs/agent-browser)"
  export UPDATE_PINS_SHELLFIRM_TAG="v$(jq -r .version "$WORK/nix/pins/shellfirm.json")"
  export UPDATE_PINS_SCHEMA_HASH="$(jq -r .hash "$WORK/nix/pins/claude-code-settings-schema.json")"
}

@test "help lists supported targets without updating pins" {
  original="$WORK/original"
  save_managed "$original"

  run_update_pins --help

  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: update-pins [target]"* ]]
  [[ "$output" == *"herdr"* ]]
  [[ "$output" == *"codex-app"* ]]
  assert_managed_matches "$original"
}

@test "unknown target is rejected without updating pins" {
  original="$WORK/original"
  save_managed "$original"

  run_update_pins unknown

  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown target 'unknown'"* ]]
  assert_managed_matches "$original"
}

@test "multiple targets are rejected without updating pins" {
  original="$WORK/original"
  save_managed "$original"

  run_update_pins herdr hcom

  [ "$status" -eq 2 ]
  [[ "$output" == *"expected at most one target"* ]]
  assert_managed_matches "$original"
}

@test "single target updates only herdr" {
  original="$WORK/original"
  save_managed "$original"
  export UPDATE_PINS_HERDR_TAG=v9.9.9

  run_update_pins herdr

  [ "$status" -eq 0 ]
  [[ "$output" == *"== herdr"* ]]
  [[ "$output" != *"== hcom"* ]]
  [ "$(jq -r .version "$WORK/nix/pins/herdr.json")" = "9.9.9" ]
  [ "$(jq -r .srcHash "$WORK/nix/pins/herdr.json")" = "sha256-src-for-test" ]
  [[ "$output" == *"herdr updated."* ]]
  cp "$WORK/nix/pins/herdr.json" "$original/nix/pins/herdr.json"
  assert_managed_matches "$original"
}

@test "single target updates only hcom and its flake input" {
  original="$WORK/original"
  save_managed "$original"
  export UPDATE_PINS_HCOM_TAG=v9.9.9

  run_update_pins hcom

  [ "$status" -eq 0 ]
  [ "$(jq -r '.assets["x86_64-linux"].hash' "$WORK/nix/pins/hcom.json")" = "sha256-asset-for-test" ]
  grep -Fq 'url = "github:aannoo/hcom/v9.9.9";' "$WORK/flake.nix"
  [ "$(jq -r .updated "$WORK/flake.lock")" = "hcom-src" ]
  grep -Fq "gh api repos/aannoo/hcom/releases/latest --jq .tag_name" "$UPDATE_PINS_COMMAND_LOG"
  grep -Fq "nix flake update hcom-src" "$UPDATE_PINS_COMMAND_LOG"
  cp "$WORK/nix/pins/hcom.json" "$original/nix/pins/hcom.json"
  cp "$WORK/flake.nix" "$original/flake.nix"
  cp "$WORK/flake.lock" "$original/flake.lock"
  assert_managed_matches "$original"
}

@test "single target updates only agent-slack and its flake input" {
  original="$WORK/original"
  save_managed "$original"
  export UPDATE_PINS_AGENT_SLACK_TAG=v9.9.9

  run_update_pins agent-slack

  [ "$status" -eq 0 ]
  [ "$(jq -r '.assets["x86_64-linux"].hash' "$WORK/nix/pins/agent-slack.json")" = "sha256-asset-for-test" ]
  grep -Fq 'url = "github:stablyai/agent-slack/v9.9.9";' "$WORK/flake.nix"
  [ "$(jq -r .updated "$WORK/flake.lock")" = "agent-slack-skill" ]
  cp "$WORK/nix/pins/agent-slack.json" "$original/nix/pins/agent-slack.json"
  cp "$WORK/flake.nix" "$original/flake.nix"
  cp "$WORK/flake.lock" "$original/flake.lock"
  assert_managed_matches "$original"
}

@test "single target updates only shellfirm" {
  original="$WORK/original"
  save_managed "$original"
  export UPDATE_PINS_SHELLFIRM_TAG=v9.9.9
  export UPDATE_PINS_SHELLFIRM_BUILD_MODE=success

  run_update_pins shellfirm

  [ "$status" -eq 0 ]
  [ "$(jq -r .version "$WORK/nix/pins/shellfirm.json")" = "9.9.9" ]
  [ "$(jq -r .srcHash "$WORK/nix/pins/shellfirm.json")" = "sha256-src-for-test" ]
  [ "$(jq -r .cargoHash "$WORK/nix/pins/shellfirm.json")" = "sha256-cargo-for-test" ]
  [ "$(cat "$UPDATE_PINS_SHELLFIRM_BUILD_COUNT")" -eq 2 ]
  cp "$WORK/nix/pins/shellfirm.json" "$original/nix/pins/shellfirm.json"
  assert_managed_matches "$original"
}

@test "shellfirm up to date does not build" {
  original="$WORK/original"
  save_managed "$original"

  run_update_pins shellfirm

  [ "$status" -eq 0 ]
  [[ "$output" == *"shellfirm: $(jq -r .version "$WORK/nix/pins/shellfirm.json") (up to date)"* ]]
  [ ! -e "$UPDATE_PINS_SHELLFIRM_BUILD_COUNT" ]
  assert_managed_matches "$original"
}

@test "single target updates only the Claude Code settings schema" {
  original="$WORK/original"
  save_managed "$original"
  export UPDATE_PINS_SCHEMA_HASH=sha256-schema-only-for-test

  run_update_pins claude-code-settings-schema

  [ "$status" -eq 0 ]
  [ "$(jq -r .hash "$WORK/nix/pins/claude-code-settings-schema.json")" = "sha256-schema-only-for-test" ]
  cp "$WORK/nix/pins/claude-code-settings-schema.json" "$original/nix/pins/claude-code-settings-schema.json"
  assert_managed_matches "$original"
}

@test "managed dirty files are rejected without changing contents" {
  printf '{"dirty":true}\n' >"$WORK/nix/pins/hcom.json"
  original="$WORK/original"
  save_managed "$original"

  run_update_pins hcom

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
  assert_no_staging_files
}

@test "successful update preserves restrictive managed file modes" {
  chmod 0440 "$WORK/nix/pins/hcom.json"
  chmod 0640 "$WORK/flake.nix"
  chmod 0600 "$WORK/flake.lock"
  original="$WORK/original"
  save_managed "$original"
  export UPDATE_PINS_HCOM_TAG=v9.9.9

  run_update_pins hcom

  [ "$status" -eq 0 ]
  chmod u+w "$original/nix/pins/hcom.json"
  cp "$WORK/nix/pins/hcom.json" "$original/nix/pins/hcom.json"
  chmod 0440 "$original/nix/pins/hcom.json"
  cp "$WORK/flake.nix" "$original/flake.nix"
  cp "$WORK/flake.lock" "$original/flake.lock"
  assert_managed_matches "$original"
  assert_no_staging_files
}

@test "failed update restores restrictive managed file modes" {
  chmod 0440 "$WORK/nix/pins/hcom.json"
  chmod 0640 "$WORK/flake.nix"
  chmod 0600 "$WORK/flake.lock"
  original="$WORK/original"
  save_managed "$original"
  export UPDATE_PINS_HCOM_TAG=v9.9.9
  export UPDATE_PINS_FAIL_FLAKE_UPDATE=hcom-src

  run_update_pins hcom

  [ "$status" -ne 0 ]
  assert_managed_matches "$original"
  assert_no_staging_files
}

@test "untracked pin file survives a failed run intact" {
  printf '{"version":"0.0.1"}\n' >"$WORK/nix/pins/newtool.json"
  original_newtool="$WORK/newtool.json.original"
  cp "$WORK/nix/pins/newtool.json" "$original_newtool"
  export UPDATE_PINS_HCOM_TAG=v1.2.3
  export UPDATE_PINS_FAIL_FLAKE_UPDATE=hcom-src

  run_update_pins

  [ "$status" -ne 0 ]
  [ -f "$WORK/nix/pins/newtool.json" ]
  cmp -s "$WORK/nix/pins/newtool.json" "$original_newtool"
}

@test "untracked pin file does not trip the dirty check" {
  printf '{"version":"0.0.1"}\n' >"$WORK/nix/pins/newtool.json"
  original_newtool="$WORK/newtool.json.original"
  cp "$WORK/nix/pins/newtool.json" "$original_newtool"
  run_update_pins

  [ "$status" -eq 0 ]
  [ -f "$WORK/nix/pins/newtool.json" ]
  cmp -s "$WORK/nix/pins/newtool.json" "$original_newtool"
}

@test "difit up to date leaves pin and lockfile unchanged" {
  original="$WORK/original"
  save_managed "$original"
  run_update_pins difit

  [ "$status" -eq 0 ]
  [[ "$output" == *"difit: $(paired_version yoshiko-pg/difit "$original/flake.nix") (up to date)"* ]]
  [[ "$output" == *"difit is up to date."* ]]
  [[ "$output" != *"All pins up to date."* ]]
  assert_managed_matches "$original"
  [ ! -e "$UPDATE_PINS_FLAKE_UPDATE_LOG" ]
}

@test "difit version bump updates pin, lockfile, and flake input" {
  original="$WORK/original"
  save_managed "$original"
  export UPDATE_PINS_DIFIT_VERSION=9.9.9
  export UPDATE_PINS_DIFIT_BUILD_MODE=success
  make_difit_tarball "$UPDATE_PINS_DIFIT_VERSION"

  run_update_pins difit

  [ "$status" -eq 0 ]
  [ "$(jq -r .srcHash "$WORK/nix/pins/difit.json")" = "sha256-difit-src-for-test" ]
  [ "$(jq -r .npmDepsHash "$WORK/nix/pins/difit.json")" = "sha256-npmdeps-for-test" ]
  [ "$(jq -r .version "$WORK/nix/packages/difit/package-lock.json")" = "9.9.9" ]
  [ "$(jq -r '.packages[""].version' "$WORK/nix/packages/difit/package-lock.json")" = "9.9.9" ]
  grep -Fq 'url = "github:yoshiko-pg/difit/v9.9.9";' "$WORK/flake.nix"
  [ "$(jq -r .updated "$WORK/flake.lock")" = "difit-src" ]
  [ "$(cat "$UPDATE_PINS_DIFIT_BUILD_COUNT")" -eq 2 ]
  npm_cwd=$(sed -n 's/^npm-cwd //p' "$UPDATE_PINS_COMMAND_LOG")
  [[ "$npm_cwd" == */package ]]
  [ "$npm_cwd" != "$WORK" ]
  cp "$WORK/nix/pins/difit.json" "$original/nix/pins/difit.json"
  cp "$WORK/nix/packages/difit/package-lock.json" "$original/nix/packages/difit/package-lock.json"
  cp "$WORK/flake.nix" "$original/flake.nix"
  cp "$WORK/flake.lock" "$original/flake.lock"
  assert_managed_matches "$original"
}

@test "difit npmDepsHash extraction failure restores everything" {
  original="$WORK/original"
  save_managed "$original"
  export UPDATE_PINS_DIFIT_VERSION=9.9.9
  export UPDATE_PINS_DIFIT_BUILD_MODE=no-hash
  make_difit_tarball "$UPDATE_PINS_DIFIT_VERSION"

  run_update_pins difit

  [ "$status" -ne 0 ]
  [[ "$output" == *"difit: failed to extract npmDepsHash"* ]]
  assert_managed_matches "$original"
}

@test "difit verification build failure restores everything" {
  original="$WORK/original"
  save_managed "$original"
  export UPDATE_PINS_DIFIT_VERSION=9.9.9
  export UPDATE_PINS_DIFIT_BUILD_MODE=verify-fails
  make_difit_tarball "$UPDATE_PINS_DIFIT_VERSION"

  run_update_pins difit

  [ "$status" -ne 0 ]
  [[ "$output" == *"difit: verification build failed"* ]]
  [ "$(cat "$UPDATE_PINS_DIFIT_BUILD_COUNT")" -eq 2 ]
  assert_managed_matches "$original"
}

@test "agent-browser version bump updates its assets and paired skill input" {
  original="$WORK/original"
  save_managed "$original"
  export UPDATE_PINS_AGENT_BROWSER_TAG=v9.9.9

  run_update_pins agent-browser

  [ "$status" -eq 0 ]
  [ "$(jq -r '.assets["x86_64-linux"].hash' "$WORK/nix/pins/agent-browser.json")" = "sha256-asset-for-test" ]
  grep -Fq 'url = "github:vercel-labs/agent-browser/v9.9.9";' "$WORK/flake.nix"
  [ "$(jq -r .updated "$WORK/flake.lock")" = "agent-browser-skill" ]
  [ "$(cat "$UPDATE_PINS_FLAKE_UPDATE_LOG")" = "agent-browser-skill" ]
  cp "$WORK/nix/pins/agent-browser.json" "$original/nix/pins/agent-browser.json"
  cp "$WORK/flake.nix" "$original/flake.nix"
  cp "$WORK/flake.lock" "$original/flake.lock"
  assert_managed_matches "$original"
}

@test "agent-browser flake update failure restores its pin and flake.lock" {
  original="$WORK/original"
  save_managed "$original"
  export UPDATE_PINS_AGENT_BROWSER_TAG=v9.9.9
  export UPDATE_PINS_FAIL_FLAKE_UPDATE=agent-browser-skill

  run_update_pins agent-browser

  [ "$status" -ne 0 ]
  assert_managed_matches "$original"
}

@test "watchexec version bump updates both Darwin assets atomically" {
  original="$WORK/original"
  save_managed "$original"
  export UPDATE_PINS_WATCHEXEC_TAG=v9.9.9

  run_update_pins watchexec

  [ "$status" -eq 0 ]
  [ "$(jq -r .version "$WORK/nix/pins/watchexec.json")" = "9.9.9" ]
  [ "$(jq -r '.assets["aarch64-darwin"].target' "$WORK/nix/pins/watchexec.json")" = "aarch64-apple-darwin" ]
  [ "$(jq -r '.assets["x86_64-darwin"].target' "$WORK/nix/pins/watchexec.json")" = "x86_64-apple-darwin" ]
  [ "$(jq -r '.assets["aarch64-darwin"].hash' "$WORK/nix/pins/watchexec.json")" = "sha256-asset-for-test" ]
  [ "$(jq -r '.assets["x86_64-darwin"].hash' "$WORK/nix/pins/watchexec.json")" = "sha256-asset-for-test" ]
  cp "$WORK/nix/pins/watchexec.json" "$original/nix/pins/watchexec.json"
  assert_managed_matches "$original"
}

@test "watchexec asset failure restores both Darwin assets" {
  original="$WORK/original"
  save_managed "$original"
  export UPDATE_PINS_WATCHEXEC_TAG=v9.9.9
  export UPDATE_PINS_FAIL_WATCHEXEC_TARGET=x86_64-apple-darwin

  run_update_pins watchexec

  [ "$status" -ne 0 ]
  [[ "$output" == *"watchexec asset prefetch failed for x86_64-apple-darwin"* ]]
  assert_managed_matches "$original"
}

@test "codex app version bump updates pin from appcast" {
  original="$WORK/original"
  save_managed "$original"
  make_unrelated_updates_noop
  export UPDATE_PINS_CODEX_APP_VERSION=26.999.10101
  export UPDATE_PINS_CODEX_APP_URL=https://persistent.oaistatic.com/codex-app-prod/ChatGPT-darwin-arm64-26.999.10101.zip

  run_update_pins codex-app

  [ "$status" -eq 0 ]
  [ "$(jq -r .version "$WORK/nix/pins/codex-app.json")" = "26.999.10101" ]
  [ "$(jq -r .url "$WORK/nix/pins/codex-app.json")" = "$UPDATE_PINS_CODEX_APP_URL" ]
  [ "$(jq -r .hash "$WORK/nix/pins/codex-app.json")" = "sha256-codex-app-for-test" ]
  [ "$(jq -r .appName "$WORK/nix/pins/codex-app.json")" = "ChatGPT.app" ]
  [ "$(jq -r .bundleIdentifier "$WORK/nix/pins/codex-app.json")" = "com.openai.codex" ]
  [ "$(jq -r .displayName "$WORK/nix/pins/codex-app.json")" = "ChatGPT" ]
  cp "$WORK/nix/pins/codex-app.json" "$original/nix/pins/codex-app.json"
  assert_managed_matches "$original"
}

@test "paired update rejects unsafe release versions before rewriting flake source" {
  original="$WORK/original"
  save_managed "$original"
  export UPDATE_PINS_HCOM_TAG='v1.2.3${builtins.readFile ./flake.nix}'

  run_update_pins hcom

  [ "$status" -ne 0 ]
  [[ "$output" == *"hcom: unsupported release version"* ]]
  assert_managed_matches "$original"
}

@test "codex app update rejects a different app name and restores managed files" {
  original="$WORK/original"
  save_managed "$original"
  export UPDATE_PINS_CODEX_APP_VERSION=26.999.10101
  export UPDATE_PINS_CODEX_APP_URL=https://persistent.oaistatic.com/codex-app-prod/ChatGPT-darwin-arm64-26.999.10101.zip
  export UPDATE_PINS_CODEX_APP_NAME=NotCodex.app

  run_update_pins codex-app

  [ "$status" -ne 0 ]
  [[ "$output" == *"expected app name ChatGPT.app but downloaded NotCodex.app"* ]]
  assert_managed_matches "$original"
}

@test "codex app update rejects a different bundle identifier and restores managed files" {
  original="$WORK/original"
  save_managed "$original"
  export UPDATE_PINS_CODEX_APP_VERSION=26.999.10101
  export UPDATE_PINS_CODEX_APP_URL=https://persistent.oaistatic.com/codex-app-prod/ChatGPT-darwin-arm64-26.999.10101.zip
  export UPDATE_PINS_CODEX_APP_BUNDLE_IDENTIFIER=com.example.not-codex

  run_update_pins codex-app

  [ "$status" -ne 0 ]
  [[ "$output" == *"expected bundle identifier com.openai.codex but downloaded com.example.not-codex"* ]]
  assert_managed_matches "$original"
}

@test "codex app update rejects a different display name and restores managed files" {
  original="$WORK/original"
  save_managed "$original"
  export UPDATE_PINS_CODEX_APP_VERSION=26.999.10101
  export UPDATE_PINS_CODEX_APP_URL=https://persistent.oaistatic.com/codex-app-prod/ChatGPT-darwin-arm64-26.999.10101.zip
  export UPDATE_PINS_CODEX_APP_DISPLAY_NAME="Not ChatGPT"

  run_update_pins codex-app

  [ "$status" -ne 0 ]
  [[ "$output" == *"expected display name ChatGPT but downloaded Not ChatGPT"* ]]
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

@test "shellfirm cargoHash extraction failure restores all managed files" {
  original="$WORK/original"
  save_managed "$original"
  export UPDATE_PINS_HCOM_TAG=v1.2.3
  export UPDATE_PINS_AGENT_SLACK_TAG=v4.5.6
  export UPDATE_PINS_SHELLFIRM_TAG=v8.8.8
  export UPDATE_PINS_SHELLFIRM_BUILD_MODE=no-hash

  run_update_pins shellfirm

  [ "$status" -ne 0 ]
  [[ "$output" == *"shellfirm: failed to extract cargoHash"* ]]
  [ "$(cat "$UPDATE_PINS_SHELLFIRM_BUILD_COUNT")" -eq 1 ]
  assert_managed_matches "$original"
}

@test "shellfirm verification build failure restores all managed files" {
  original="$WORK/original"
  save_managed "$original"
  export UPDATE_PINS_SHELLFIRM_TAG=v8.8.8
  export UPDATE_PINS_SHELLFIRM_BUILD_MODE=verify-fails

  run_update_pins shellfirm

  [ "$status" -ne 0 ]
  [[ "$output" == *"shellfirm: verification build failed"* ]]
  [ "$(cat "$UPDATE_PINS_SHELLFIRM_BUILD_COUNT")" -eq 2 ]
  assert_managed_matches "$original"
}

@test "herdr source prefetch failure restores all managed files" {
  original="$WORK/original"
  save_managed "$original"
  export UPDATE_PINS_HCOM_TAG=v1.2.3
  export UPDATE_PINS_AGENT_SLACK_TAG=v4.5.6
  export UPDATE_PINS_HERDR_TAG=v9.9.9
  export UPDATE_PINS_FAIL_HERDR_PREFETCH=source

  run_update_pins

  [ "$status" -ne 0 ]
  [[ "$output" == *"herdr source prefetch failed"* ]]
  assert_managed_matches "$original"
}

@test "successful update leaves expected managed file changes" {
  original="$WORK/original"
  save_managed "$original"
  export UPDATE_PINS_HCOM_TAG=v1.2.3
  export UPDATE_PINS_AGENT_SLACK_TAG=v4.5.6
  export UPDATE_PINS_SHELLFIRM_TAG=v8.8.8
  export UPDATE_PINS_HERDR_TAG=v9.9.9
  export UPDATE_PINS_SHELLFIRM_BUILD_MODE=success

  run_update_pins

  [ "$status" -eq 0 ]
  grep -Fq 'url = "github:aannoo/hcom/v1.2.3";' "$WORK/flake.nix"
  [ "$(jq -r '.assets["aarch64-darwin"].hash' "$WORK/nix/pins/hcom.json")" = "sha256-asset-for-test" ]
  grep -Fq 'url = "github:stablyai/agent-slack/v4.5.6";' "$WORK/flake.nix"
  [ "$(jq -r .version "$WORK/nix/pins/shellfirm.json")" = "8.8.8" ]
  [ "$(jq -r .srcHash "$WORK/nix/pins/shellfirm.json")" = "sha256-src-for-test" ]
  [ "$(jq -r .cargoHash "$WORK/nix/pins/shellfirm.json")" = "sha256-cargo-for-test" ]
  [ "$(jq -r .version "$WORK/nix/pins/herdr.json")" = "9.9.9" ]
  [ "$(jq -r .srcHash "$WORK/nix/pins/herdr.json")" = "sha256-src-for-test" ]
  [ "$(jq -r '.assets["x86_64-linux"].hash' "$WORK/nix/pins/herdr.json")" = "sha256-asset-for-test" ]
  [ "$(jq -r .hash "$WORK/nix/pins/claude-code-settings-schema.json")" = "sha256-schema-for-test" ]
  [ "$(jq -r .updated "$WORK/flake.lock")" = "agent-slack-skill" ]
  [ "$(cat "$UPDATE_PINS_FLAKE_UPDATE_LOG")" = $'hcom-src\nagent-slack-skill' ]
  ! assert_managed_matches "$original"
  assert_no_staging_files
}

@test "repeating a successful update is byte and mode stable" {
  export UPDATE_PINS_HCOM_TAG=v1.2.3
  export UPDATE_PINS_AGENT_SLACK_TAG=v4.5.6
  export UPDATE_PINS_SHELLFIRM_TAG=v8.8.8
  export UPDATE_PINS_HERDR_TAG=v9.9.9
  export UPDATE_PINS_SHELLFIRM_BUILD_MODE=success

  run_update_pins

  [ "$status" -eq 0 ]
  after_first="$WORK/after-first"
  save_managed "$after_first"
  git -C "$WORK" add flake.nix flake.lock nix/packages/difit/package-lock.json nix/pins/*.json
  git -C "$WORK" commit -q -m "apply first update"

  run_update_pins

  [ "$status" -eq 0 ]
  [[ "$output" == *"All pins up to date."* ]]
  assert_managed_matches "$after_first"
}
