#!/usr/bin/env bats
# update-pins の全体 transaction を fake repo とスタブだけで検査する。

setup() {
  REPO_ROOT="$(git rev-parse --show-toplevel)"
  WORK="$(mktemp -d)"
  mkdir -p "$WORK/nix/apps" "$WORK/nix/pins" "$WORK/nix/packages/difit"
  cp "$REPO_ROOT/nix/apps/update-pins.sh" "$WORK/nix/apps/update-pins.sh"
  cp "$REPO_ROOT"/nix/pins/*.json "$WORK/nix/pins/"
  cp "$REPO_ROOT/nix/packages/difit/package-lock.json" "$WORK/nix/packages/difit/package-lock.json"
  cp "$REPO_ROOT/flake.lock" "$WORK/flake.lock"

  (
    cd "$WORK"
    git init -q
    git config user.email update-pins-test@example.invalid
    git config user.name "update-pins test"
    git config commit.gpgsign false
    git add flake.lock nix/apps/update-pins.sh nix/packages/difit/package-lock.json nix/pins/*.json
    git commit -q -m "initial managed files"
  )

  STUB_DIR="$WORK/stub"
  mkdir -p "$STUB_DIR"
  export UPDATE_PINS_FAKE_ROOT="$WORK"
  export UPDATE_PINS_NIX_BUILD_COUNT="$WORK/nix-build-count"
  export UPDATE_PINS_SHELLFIRM_BUILD_COUNT="$WORK/shellfirm-build-count"
  export UPDATE_PINS_DIFIT_BUILD_COUNT="$WORK/difit-build-count"

  mkdir -p "$WORK/difit-tar/package"
  cat >"$WORK/difit-tar/package/package.json" <<'EOS'
{"name":"difit","version":"0.0.0"}
EOS
  tar -czf "$WORK/difit.tgz" -C "$WORK/difit-tar" package
  export UPDATE_PINS_DIFIT_TARBALL="$WORK/difit.tgz"

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
"api repos/vercel-labs/agent-browser/releases/latest --jq .tag_name")
  printf '%s\n' "${UPDATE_PINS_AGENT_BROWSER_TAG:-v$(jq -r .version "$UPDATE_PINS_FAKE_ROOT/nix/pins/agent-browser.json")}"
  ;;
"api repos/k1LoW/git-wt/releases/latest --jq .tag_name")
  printf '%s\n' "${UPDATE_PINS_GIT_WT_TAG:-v999.0.0}"
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

  cat >"$STUB_DIR/curl" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail

if [ "$1" != "-fsSL" ]; then
  echo "unexpected curl invocation: $*" >&2
  exit 1
fi

case "${2:-}" in
https://registry.npmjs.org/difit/latest)
  printf '{"version":"%s"}\n' "${UPDATE_PINS_DIFIT_VERSION:-$(jq -r .version "$UPDATE_PINS_FAKE_ROOT/nix/pins/difit.json")}"
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

  cat >"$STUB_DIR/npm" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail

if [ "$1" = "install" ] && [[ " $* " == *" --package-lock-only "* ]]; then
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

  cat >"$STUB_DIR/nix" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail

if [ "$1" = "store" ] && [ "${2:-}" = "prefetch-file" ]; then
  if [[ " $* " == *"github.com/ogulcancelik/herdr/archive/refs/tags/"* ]] && [ "${UPDATE_PINS_FAIL_HERDR_PREFETCH:-}" = "source" ]; then
    echo "herdr source prefetch failed" >&2
    exit 1
  fi
  if [[ " $* " == *"persistent.oaistatic.com/codex-app-prod/"*".zip"* ]]; then
    zip_path="$UPDATE_PINS_FAKE_ROOT/codex-app.zip"
    app_name=${UPDATE_PINS_CODEX_APP_NAME:-ChatGPT.app}
    version=${UPDATE_PINS_CODEX_APP_BUNDLE_VERSION:-${UPDATE_PINS_CODEX_APP_VERSION:-$(jq -r .version "$UPDATE_PINS_FAKE_ROOT/nix/pins/codex-app.json")}}
    python3 - "$zip_path" "$app_name" "$version" <<'PY'
import plistlib
import sys
import zipfile

zip_path, app_name, version = sys.argv[1:]
plist = {
    "CFBundleDisplayName": "ChatGPT",
    "CFBundleIdentifier": "com.openai.codex",
    "CFBundleName": "ChatGPT",
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
    printf '{"hash":"sha256-difit-src-for-test"}\n'
    exit 0
  fi
  if [[ " $* " == *" --unpack "* ]]; then
    printf '{"hash":"sha256-src-for-test"}\n'
  else
    printf '{"hash":"sha256-asset-for-test"}\n'
  fi
  exit 0
fi

if [ "$1" = "build" ] && [ "${2:-}" = "--impure" ] && [ "${3:-}" = "--expr" ] && [ "${5:-}" = "--no-link" ] && [ "${UPDATE_PINS_PACKAGE:-}" = "git-wt" ]; then
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
      echo "error: hash mismatch"
      echo "got: sha256-cargo-for-test"
      exit 1
    fi
    exit 0
    ;;
  verify-fails)
    if [ "$count" -eq 1 ]; then
      echo "error: hash mismatch"
      echo "got: sha256-cargo-for-test"
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
      echo "error: hash mismatch"
      echo "got: sha256-npmdeps-for-test"
      exit 1
    fi
    exit 0
    ;;
  verify-fails)
    if [ "$count" -eq 1 ]; then
      echo "error: hash mismatch"
      echo "got: sha256-npmdeps-for-test"
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
  run bash -eu -o pipefail -c 'cd "$UPDATE_PINS_FAKE_ROOT"; bash -eu -o pipefail nix/apps/update-pins.sh 2>&1'
}

save_managed() {
  local dst=$1
  mkdir -p "$dst/nix/pins" "$dst/nix/packages/difit"
  cp "$WORK/flake.lock" "$dst/flake.lock"
  cp "$WORK"/nix/pins/*.json "$dst/nix/pins/"
  cp "$WORK/nix/packages/difit/package-lock.json" "$dst/nix/packages/difit/package-lock.json"
}

assert_managed_matches() {
  local expected=$1 pin name
  cmp -s "$WORK/flake.lock" "$expected/flake.lock" || return 1
  cmp -s "$WORK/nix/packages/difit/package-lock.json" "$expected/nix/packages/difit/package-lock.json" || return 1
  for pin in "$expected"/nix/pins/*.json; do
    name=$(basename "$pin")
    cmp -s "$WORK/nix/pins/$name" "$pin" || return 1
  done
}

make_unrelated_updates_noop() {
  export UPDATE_PINS_AGENT_BROWSER_TAG="v$(jq -r .version "$WORK/nix/pins/agent-browser.json")"
  export UPDATE_PINS_GIT_WT_TAG="v$(jq -r .version "$WORK/nix/pins/git-wt.json")"
  export UPDATE_PINS_SHELLFIRM_TAG="v$(jq -r .version "$WORK/nix/pins/shellfirm.json")"
  export UPDATE_PINS_SCHEMA_HASH="$(jq -r .hash "$WORK/nix/pins/claude-code-settings-schema.json")"
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
  export UPDATE_PINS_BUILD_MODE=success

  run_update_pins

  [ "$status" -eq 0 ]
  [ -f "$WORK/nix/pins/newtool.json" ]
  cmp -s "$WORK/nix/pins/newtool.json" "$original_newtool"
}

@test "difit up to date leaves pin and lockfile unchanged" {
  original="$WORK/original"
  save_managed "$original"
  make_unrelated_updates_noop

  run_update_pins

  [ "$status" -eq 0 ]
  [[ "$output" == *"difit: $(jq -r .version "$original/nix/pins/difit.json") (up to date)"* ]]
  cmp -s "$WORK/nix/pins/difit.json" "$original/nix/pins/difit.json"
  cmp -s "$WORK/nix/packages/difit/package-lock.json" "$original/nix/packages/difit/package-lock.json"
}

@test "difit version bump updates pin, lockfile, and flake input" {
  original="$WORK/original"
  save_managed "$original"
  make_unrelated_updates_noop
  export UPDATE_PINS_DIFIT_VERSION=9.9.9
  export UPDATE_PINS_DIFIT_BUILD_MODE=success

  run_update_pins

  [ "$status" -eq 0 ]
  [ "$(jq -r .version "$WORK/nix/pins/difit.json")" = "9.9.9" ]
  [ "$(jq -r .srcHash "$WORK/nix/pins/difit.json")" = "sha256-difit-src-for-test" ]
  [ "$(jq -r .npmDepsHash "$WORK/nix/pins/difit.json")" = "sha256-npmdeps-for-test" ]
  [ "$(jq -r .version "$WORK/nix/packages/difit/package-lock.json")" = "9.9.9" ]
  [ "$(jq -r '.packages[""].version' "$WORK/nix/packages/difit/package-lock.json")" = "9.9.9" ]
  [ "$(jq -r .updated "$WORK/flake.lock")" = "difit-src" ]
  ! assert_managed_matches "$original"
}

@test "difit npmDepsHash extraction failure restores everything" {
  original="$WORK/original"
  save_managed "$original"
  make_unrelated_updates_noop
  export UPDATE_PINS_DIFIT_VERSION=9.9.9
  export UPDATE_PINS_DIFIT_BUILD_MODE=no-hash

  run_update_pins

  [ "$status" -ne 0 ]
  [[ "$output" == *"difit: failed to extract npmDepsHash"* ]]
  assert_managed_matches "$original"
}

@test "codex app version bump updates pin from appcast" {
  original="$WORK/original"
  save_managed "$original"
  make_unrelated_updates_noop
  export UPDATE_PINS_CODEX_APP_VERSION=26.999.10101
  export UPDATE_PINS_CODEX_APP_URL=https://persistent.oaistatic.com/codex-app-prod/ChatGPT-darwin-arm64-26.999.10101.zip

  run_update_pins

  [ "$status" -eq 0 ]
  [ "$(jq -r .version "$WORK/nix/pins/codex-app.json")" = "26.999.10101" ]
  [ "$(jq -r .url "$WORK/nix/pins/codex-app.json")" = "$UPDATE_PINS_CODEX_APP_URL" ]
  [ "$(jq -r .hash "$WORK/nix/pins/codex-app.json")" = "sha256-codex-app-for-test" ]
  [ "$(jq -r .appName "$WORK/nix/pins/codex-app.json")" = "ChatGPT.app" ]
  [ "$(jq -r .bundleIdentifier "$WORK/nix/pins/codex-app.json")" = "com.openai.codex" ]
  [ "$(jq -r .displayName "$WORK/nix/pins/codex-app.json")" = "ChatGPT" ]
  ! assert_managed_matches "$original"
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

@test "shellfirm cargoHash extraction failure restores all managed files" {
  original="$WORK/original"
  save_managed "$original"
  export UPDATE_PINS_HCOM_TAG=v1.2.3
  export UPDATE_PINS_AGENT_SLACK_TAG=v4.5.6
  export UPDATE_PINS_BUILD_MODE=success
  export UPDATE_PINS_SHELLFIRM_TAG=v8.8.8
  export UPDATE_PINS_SHELLFIRM_BUILD_MODE=no-hash

  run_update_pins

  [ "$status" -ne 0 ]
  [[ "$output" == *"shellfirm: failed to extract cargoHash"* ]]
  assert_managed_matches "$original"
}

@test "herdr source prefetch failure restores all managed files" {
  original="$WORK/original"
  save_managed "$original"
  export UPDATE_PINS_HCOM_TAG=v1.2.3
  export UPDATE_PINS_AGENT_SLACK_TAG=v4.5.6
  export UPDATE_PINS_BUILD_MODE=success
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
  export UPDATE_PINS_BUILD_MODE=success
  export UPDATE_PINS_SHELLFIRM_BUILD_MODE=success

  run_update_pins

  [ "$status" -eq 0 ]
  [ "$(jq -r .version "$WORK/nix/pins/hcom.json")" = "1.2.3" ]
  [ "$(jq -r '.assets["aarch64-darwin"].hash' "$WORK/nix/pins/hcom.json")" = "sha256-asset-for-test" ]
  [ "$(jq -r .version "$WORK/nix/pins/agent-slack.json")" = "4.5.6" ]
  [ "$(jq -r .version "$WORK/nix/pins/git-wt.json")" = "999.0.0" ]
  [ "$(jq -r .srcHash "$WORK/nix/pins/git-wt.json")" = "sha256-src-for-test" ]
  [ "$(jq -r .vendorHash "$WORK/nix/pins/git-wt.json")" = "sha256-vendor-for-test" ]
  [ "$(jq -r .version "$WORK/nix/pins/shellfirm.json")" = "8.8.8" ]
  [ "$(jq -r .srcHash "$WORK/nix/pins/shellfirm.json")" = "sha256-src-for-test" ]
  [ "$(jq -r .cargoHash "$WORK/nix/pins/shellfirm.json")" = "sha256-cargo-for-test" ]
  [ "$(jq -r .version "$WORK/nix/pins/herdr.json")" = "9.9.9" ]
  [ "$(jq -r .srcHash "$WORK/nix/pins/herdr.json")" = "sha256-src-for-test" ]
  [ "$(jq -r '.assets["x86_64-linux"].hash' "$WORK/nix/pins/herdr.json")" = "sha256-asset-for-test" ]
  [ "$(jq -r .hash "$WORK/nix/pins/claude-code-settings-schema.json")" = "sha256-schema-for-test" ]
  [ "$(jq -r .updated "$WORK/flake.lock")" = "agent-slack-skill" ]
  ! assert_managed_matches "$original"
}
