#!/usr/bin/env bats
# update-pins の全体 transaction を fake repo とスタブだけで検査する。

make_difit_tarball() {
  local version=$1
  mkdir -p "$WORK/difit-tar/package"
  printf '{"name":"difit","version":"%s"}\n' "$version" >"$WORK/difit-tar/package/package.json"
  tar -czf "$WORK/difit.tgz" -C "$WORK/difit-tar" package
  export UPDATE_PINS_DIFIT_TARBALL="$WORK/difit.tgz"
}

make_source_tarball() {
  mkdir -p "$WORK/source-tar/source"
  printf 'source fixture\n' >"$WORK/source-tar/source/README"
  tar -czf "$WORK/source.tar.gz" -C "$WORK/source-tar" source
  export UPDATE_PINS_SOURCE_TARBALL="$WORK/source.tar.gz"
}

setup() {
  REPO_ROOT="$(git rev-parse --show-toplevel)"
  BASH_BIN="$(command -v bash)"
  WORK="$(mktemp -d)"
  mkdir -p "$WORK/nix/pins" "$WORK/nix/packages/difit" "$WORK/nix/packages/shellfirm"
  cp "$REPO_ROOT"/nix/pins/*.json "$WORK/nix/pins/"
  cp "$REPO_ROOT/nix/packages/difit/package-lock.json" "$WORK/nix/packages/difit/package-lock.json"
  cp "$REPO_ROOT/nix/packages/shellfirm/Cargo.lock" "$WORK/nix/packages/shellfirm/Cargo.lock"
  cp "$REPO_ROOT/flake.nix" "$WORK/flake.nix"
  cp "$REPO_ROOT/flake.lock" "$WORK/flake.lock"

  (
    cd "$WORK"
    git init -q
    git config user.email update-pins-test@example.invalid
    git config user.name "update-pins test"
    git config commit.gpgsign false
    git add flake.nix flake.lock nix/packages/difit/package-lock.json nix/packages/shellfirm/Cargo.lock nix/pins/*.json
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
    echo "UPDATE_PINS_TEST_BIN must identify the unwrapped update-pins binary" >&2
    return 1
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

  make_difit_tarball "$(sed -n 's|.*github:yoshiko-pg/difit/v\([^"]*\)";|\1|p' "$WORK/flake.nix")"
  make_source_tarball

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

gh_response() {
  printf 'HTTP/2.0 200 OK\r\ncontent-type: application/json\r\n\r\n'
  jq -cn --arg tag "$1" '{tag_name: $tag}'
}

case "$*" in
"api --include repos/aannoo/hcom/releases/latest")
  gh_response "${UPDATE_PINS_HCOM_TAG:-v$(flake_version aannoo/hcom)}"
  ;;
"api --include repos/stablyai/agent-slack/releases/latest")
  gh_response "${UPDATE_PINS_AGENT_SLACK_TAG:-v$(flake_version stablyai/agent-slack)}"
  ;;
"api --include repos/vercel-labs/agent-browser/releases/latest")
  gh_response "${UPDATE_PINS_AGENT_BROWSER_TAG:-v$(flake_version vercel-labs/agent-browser)}"
  ;;
"api --include repos/watchexec/watchexec/releases/latest")
  gh_response "${UPDATE_PINS_WATCHEXEC_TAG:-v$(jq -r .version "$UPDATE_PINS_FAKE_ROOT/nix/pins/watchexec.json")}"
  ;;
"api --include repos/kaplanelad/shellfirm/releases/latest")
  gh_response "${UPDATE_PINS_SHELLFIRM_TAG:-v$(jq -r .version "$UPDATE_PINS_FAKE_ROOT/nix/pins/shellfirm.json")}"
  ;;
"api --include repos/ogulcancelik/herdr/releases/latest")
  gh_response "${UPDATE_PINS_HERDR_TAG:-v$(jq -r .version "$UPDATE_PINS_FAKE_ROOT/nix/pins/herdr.json")}"
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

if [ "$#" -ne 17 ] \
  || [ "$1" != "-sS" ] \
  || [ "$2" != "--location" ] \
  || [ "$3" != "--proto" ] \
  || [ "$4" != "=https" ] \
  || [ "$5" != "--proto-redir" ] \
  || [ "$6" != "=https" ] \
  || [ "$7" != "--connect-timeout" ] \
  || [ "$8" != "15" ] \
  || [ "$9" != "--max-time" ] \
  || [ "${10}" != "110" ] \
  || [ "${11}" != "--max-filesize" ] \
  || ! [[ "${12}" =~ ^[1-9][0-9]*$ ]] \
  || [ "${13}" != "--output" ] \
  || [ "${15}" != "--write-out" ] \
  || [ "${16}" != "%{http_code}" ]; then
  echo "unexpected curl invocation: $*" >&2
  exit 1
fi

output_path=${14}
url=${17}
if [ -n "${UPDATE_PINS_CURL_FAIL_PATTERN:-}" ] \
  && [[ "$url" == *"$UPDATE_PINS_CURL_FAIL_PATTERN"* ]]; then
  count=0
  if [ -f "$UPDATE_PINS_FAKE_ROOT/curl-failure-count" ]; then
    count=$(cat "$UPDATE_PINS_FAKE_ROOT/curl-failure-count")
  fi
  count=$((count + 1))
  printf '%s\n' "$count" >"$UPDATE_PINS_FAKE_ROOT/curl-failure-count"
  if [ "$count" -le "${UPDATE_PINS_CURL_FAIL_COUNT:-0}" ]; then
    printf '%s' "${UPDATE_PINS_CURL_FAIL_HTTP_STATUS:-503}"
    exit "${UPDATE_PINS_CURL_FAIL_EXIT_STATUS:-0}"
  fi
fi
if [ "${UPDATE_PINS_FAIL_HERDR_PREFETCH:-}" = "source" ] \
  && [[ "$url" == *"github.com/ogulcancelik/herdr/archive/refs/tags/"* ]]; then
  printf '000'
  exit 7
fi
if [ -n "${UPDATE_PINS_FAIL_WATCHEXEC_TARGET:-}" ] \
  && [[ "$url" == *"github.com/watchexec/watchexec/releases/download/"*"$UPDATE_PINS_FAIL_WATCHEXEC_TARGET"* ]]; then
  printf '000'
  exit 7
fi

case "$url" in
https://registry.npmjs.org/difit/latest)
  if [ "${UPDATE_PINS_INVALID_NPM_JSON:-}" = "1" ]; then
    printf '{invalid\n' >"$output_path"
  else
    printf '{"version":"%s"}\n' "${UPDATE_PINS_DIFIT_VERSION:-$(flake_version yoshiko-pg/difit)}" >"$output_path"
  fi
  ;;
https://registry.npmjs.org/difit/-/difit-*.tgz)
  cp "$UPDATE_PINS_DIFIT_TARBALL" "$output_path"
  ;;
https://persistent.oaistatic.com/codex-app-prod/appcast.xml)
  version=${UPDATE_PINS_CODEX_APP_VERSION:-$(jq -r .version "$UPDATE_PINS_FAKE_ROOT/nix/pins/codex-app.json")}
  url=${UPDATE_PINS_CODEX_APP_URL:-$(jq -r .url "$UPDATE_PINS_FAKE_ROOT/nix/pins/codex-app.json")}
  cat >"$output_path" <<XML
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
https://persistent.oaistatic.com/codex-app-prod/*.zip)
  app_name=${UPDATE_PINS_CODEX_APP_NAME:-$(jq -r .appName "$UPDATE_PINS_FAKE_ROOT/nix/pins/codex-app.json")}
  bundle_identifier=${UPDATE_PINS_CODEX_APP_BUNDLE_IDENTIFIER:-$(jq -r .bundleIdentifier "$UPDATE_PINS_FAKE_ROOT/nix/pins/codex-app.json")}
  display_name=${UPDATE_PINS_CODEX_APP_DISPLAY_NAME:-$(jq -r .displayName "$UPDATE_PINS_FAKE_ROOT/nix/pins/codex-app.json")}
  version=${UPDATE_PINS_CODEX_APP_BUNDLE_VERSION:-${UPDATE_PINS_CODEX_APP_VERSION:-$(jq -r .version "$UPDATE_PINS_FAKE_ROOT/nix/pins/codex-app.json")}}
  python3 - "$output_path" "$app_name" "$bundle_identifier" "$display_name" "$version" <<'PY'
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
  ;;
https://json.schemastore.org/claude-code-settings.json)
  printf '{}\n' >"$output_path"
  ;;
https://github.com/kaplanelad/shellfirm/archive/refs/tags/*.tar.gz)
  cp "$UPDATE_PINS_SOURCE_TARBALL" "$output_path"
  printf '%s\n' "$output_path" >"$UPDATE_PINS_FAKE_ROOT/shellfirm-download-path"
  ;;
https://github.com/ogulcancelik/herdr/archive/refs/tags/*.tar.gz)
  cp "$UPDATE_PINS_SOURCE_TARBALL" "$output_path"
  ;;
https://github.com/*)
  printf 'artifact fixture\n' >"$output_path"
  ;;
*)
  echo "unexpected curl invocation: $*" >&2
  exit 1
  ;;
esac
printf '200'
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

if [ "${UPDATE_PINS_FAIL_NPM_INSTALL:-}" = "1" ]; then
  echo "npm install failed" >&2
  exit 1
fi

if [ "$#" -eq 5 ] \
  && [ "$1" = "install" ] \
  && [ "$2" = "--package-lock-only" ] \
  && [ "$3" = "--ignore-scripts" ] \
  && [ "$4" = "--no-audit" ] \
  && [ "$5" = "--no-fund" ]; then
  if [ "${UPDATE_PINS_DIFIT_REUSE_LOCK:-}" = "1" ]; then
    cp "$UPDATE_PINS_FAKE_ROOT/nix/packages/difit/package-lock.json" package-lock.json
    exit 0
  fi
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

if { [ "$#" -eq 6 ] || [ "$#" -eq 7 ]; } \
  && [ "$1" = "store" ] \
  && [ "$2" = "prefetch-file" ] \
  && [ "$3" = "--json" ] \
  && [ "$4" = "--name" ] \
  && [[ "$5" == update-pins-* ]]; then
  if [ "$#" -eq 7 ] && [ "$6" != "--unpack" ]; then
    echo "unexpected nix prefetch invocation: $*" >&2
    exit 1
  fi
  local_url=${!#}
  case "$local_url" in
  file:///*) local_path=${local_url#file://} ;;
  *)
    echo "nix prefetch did not receive a local download: $*" >&2
    exit 1
    ;;
  esac
  if [ ! -f "$local_path" ]; then
    echo "nix prefetch local download is missing: $local_path" >&2
    exit 1
  fi
  if [ -f "$UPDATE_PINS_FAKE_ROOT/shellfirm-download-path" ] \
    && [ "$(cat "$UPDATE_PINS_FAKE_ROOT/shellfirm-download-path")" = "$local_path" ]; then
    store="$UPDATE_PINS_FAKE_ROOT/shellfirm-store"
    mkdir -p "$store/shellfirm"
    version=${UPDATE_PINS_SHELLFIRM_TAG:-v$(jq -r .version "$UPDATE_PINS_FAKE_ROOT/nix/pins/shellfirm.json")}
    version=${version#v}
    printf '[workspace]\nmembers = ["shellfirm"]\n' >"$store/Cargo.toml"
    printf '[package]\nname = "shellfirm"\nversion = "%s"\n' "$version" >"$store/shellfirm/Cargo.toml"
    if [ "${UPDATE_PINS_SHELLFIRM_LOCK_MODE:-}" != "missing" ]; then
      if [ "${UPDATE_PINS_SHELLFIRM_REUSE_LOCK:-}" = "1" ]; then
        cp "$UPDATE_PINS_FAKE_ROOT/nix/packages/shellfirm/Cargo.lock" "$store/Cargo.lock"
      else
        lock_version=$version
        registry_source=registry+https://github.com/rust-lang/crates.io-index
        if [ "${UPDATE_PINS_SHELLFIRM_LOCK_MODE:-}" = "version-mismatch" ]; then
          lock_version=0.0.0
        fi
        if [ "${UPDATE_PINS_SHELLFIRM_LOCK_MODE:-}" = "alternate-registry" ]; then
          registry_source=registry+https://example.invalid/index
        fi
        cat >"$store/Cargo.lock" <<LOCK
version = 4

[[package]]
name = "fixture-dependency"
version = "1.0.0"
source = "$registry_source"
checksum = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

[[package]]
name = "shellfirm"
version = "$lock_version"
LOCK
        if [ "${UPDATE_PINS_SHELLFIRM_LOCK_MODE:-}" = "git-dependency" ]; then
          cat >>"$store/Cargo.lock" <<'LOCK'

[[package]]
name = "git-fixture"
version = "1.0.0"
source = "git+https://example.invalid/repository"
LOCK
        fi
      fi
    fi
    if [ "${UPDATE_PINS_SHELLFIRM_LOCK_MODE:-}" = "ambiguous" ]; then
      mkdir -p "$store/nested"
      printf '[workspace]\n' >"$store/nested/Cargo.toml"
      printf 'version = 4\n' >"$store/nested/Cargo.lock"
    fi
    printf '{"hash":"%s","storePath":"%s"}\n' "${UPDATE_PINS_SOURCE_HASH:-sha256-JaZjQmPBsfb8RpegTiuZBOpLBCqJr1nck+wfXUSEiiY=}" "$store"
    exit 0
  fi
  case "$local_path" in
  *.zip)
    zip_path="$UPDATE_PINS_FAKE_ROOT/codex-app.zip"
    cp "$local_path" "$zip_path"
    printf '{"hash":"sha256-V95M9AFEvffQABDy9VV6fWQsK5cFMJv63hZ90xPiypM=","storePath":"%s"}\n' "$zip_path"
    exit 0
    ;;
  *.json)
    printf '{"hash":"%s"}\n' "${UPDATE_PINS_SCHEMA_HASH:-sha256-3wrW5DiA8JyQ6/lfGREBeKumiQ3wAQ69p0hQKeK1Q7Q=}"
    exit 0
    ;;
  *.tgz)
    printf '{"hash":"%s","storePath":"%s"}\n' "${UPDATE_PINS_DIFIT_SOURCE_HASH:-sha256-gmer9Ei3Jq/YwFQ13VuGqxjSZiafe7wWoJnabLgSrKE=}" "$UPDATE_PINS_DIFIT_TARBALL"
    exit 0
    ;;
  esac
  if [ "$#" -eq 7 ]; then
    printf '{"hash":"%s"}\n' "${UPDATE_PINS_SOURCE_HASH:-sha256-JaZjQmPBsfb8RpegTiuZBOpLBCqJr1nck+wfXUSEiiY=}"
  else
    printf '{"hash":"%s"}\n' "${UPDATE_PINS_ASSET_HASH:-sha256-1ZOG4K5DXikvvg6825VLde1fs5IgkSd8sZ95j8XVBxg=}"
  fi
  exit 0
fi

if [ "$1" = "build" ] \
  && [ "${2:-}" = "--impure" ] \
  && [ "${3:-}" = "--expr" ] \
  && { [[ "${4:-}" != *"pkgs.dotfilesPackages"* ]] || [[ "${4:-}" != *'builtins.getEnv "UPDATE_PINS_PACKAGE"'* ]]; }; then
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
  success)
    exit 0
    ;;
  fails)
    echo "candidate package build failed" >&2
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
      echo "got: sha256-32X0K6wkLW2x9cJJJ6J+cu5HOM2+oTZe5AEqLRHvpPM=" >&2
      exit 1
    fi
    exit 0
    ;;
  verify-fails)
    if [ "$count" -eq 1 ]; then
      echo "error: hash mismatch" >&2
      echo "got: sha256-32X0K6wkLW2x9cJJJ6J+cu5HOM2+oTZe5AEqLRHvpPM=" >&2
      exit 1
    fi
    echo "verification build failed" >&2
    exit 1
    ;;
  verify-existing)
    if [ "$count" -eq 1 ]; then
      [[ "${4:-}" == *"pkgs.lib.fakeHash"* ]]
      [ -n "${UPDATE_PINS_PIN_JSON:-}" ]
      echo "error: hash mismatch" >&2
      echo "got: ${UPDATE_PINS_REFRESHED_NPM_HASH:?}" >&2
      exit 1
    fi
    exit 0
    ;;
  refresh-existing)
    if [ "$count" -eq 1 ]; then
      echo "error: hash mismatch" >&2
      echo "got: ${UPDATE_PINS_REFRESHED_NPM_HASH:?}" >&2
      exit 1
    fi
    exit 0
    ;;
  verify-existing-fails)
    echo "existing npmDepsHash verification failed" >&2
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
  case "$input" in
  hcom-src) repo=aannoo/hcom ;;
  agent-slack-skill) repo=stablyai/agent-slack ;;
  agent-browser-skill) repo=vercel-labs/agent-browser ;;
  difit-src) repo=yoshiko-pg/difit ;;
  *)
    echo "unexpected flake input: $input" >&2
    exit 1
    ;;
  esac
  version=$(sed -n "s|.*github:$repo/v\\([^\"]*\\)\";|\\1|p" "$UPDATE_PINS_FAKE_ROOT/flake.nix")
  node=$(jq -r --arg input "$input" '.nodes[.root].inputs[$input]' "$UPDATE_PINS_FAKE_ROOT/flake.lock")
  jq \
    --arg node "$node" \
    --arg ref "v$version" \
    --arg rev "fixture-$input-v$version" \
    '.nodes[$node].original.ref = $ref | .nodes[$node].locked.rev = $rev' \
    "$UPDATE_PINS_FAKE_ROOT/flake.lock" >"$UPDATE_PINS_FAKE_ROOT/flake.lock.new"
  mv "$UPDATE_PINS_FAKE_ROOT/flake.lock.new" "$UPDATE_PINS_FAKE_ROOT/flake.lock"
  if [ "${UPDATE_PINS_FAIL_FLAKE_UPDATE:-}" = "$input" ]; then
    echo "flake update failed for $input" >&2
    exit 1
  fi
  if [ "${UPDATE_PINS_BREAK_ROLLBACK:-}" = "$input" ]; then
    rm "$UPDATE_PINS_FAKE_ROOT/flake.lock"
    mkdir "$UPDATE_PINS_FAKE_ROOT/flake.lock"
    echo "flake update failed before rollback" >&2
    exit 1
  fi
  if [ "${UPDATE_PINS_DELETE_FLAKE_AFTER_UPDATE:-}" = "$input" ]; then
    rm "$UPDATE_PINS_FAKE_ROOT/flake.lock"
    exit 0
  fi
  if [ "${UPDATE_PINS_CORRUPT_FLAKE_AFTER_UPDATE:-}" = "$input" ]; then
    printf '\n# url = "github:aannoo/hcom/v0.0.0";\n' >>"$UPDATE_PINS_FAKE_ROOT/flake.nix"
  fi
  echo "Updated input $input with secret-before-commit" >&2
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
  mkdir -p "$dst/nix/pins" "$dst/nix/packages/difit" "$dst/nix/packages/shellfirm"
  cp -p "$WORK/flake.nix" "$dst/flake.nix"
  cp -p "$WORK/flake.lock" "$dst/flake.lock"
  cp -p "$WORK"/nix/pins/*.json "$dst/nix/pins/"
  cp -p "$WORK/nix/packages/difit/package-lock.json" "$dst/nix/packages/difit/package-lock.json"
  cp -p "$WORK/nix/packages/shellfirm/Cargo.lock" "$dst/nix/packages/shellfirm/Cargo.lock"
}

assert_managed_matches() {
  local expected=$1 pin name
  cmp -s "$WORK/flake.nix" "$expected/flake.nix" || return 1
  assert_same_mode "$WORK/flake.nix" "$expected/flake.nix" || return 1
  cmp -s "$WORK/flake.lock" "$expected/flake.lock" || return 1
  assert_same_mode "$WORK/flake.lock" "$expected/flake.lock" || return 1
  cmp -s "$WORK/nix/packages/difit/package-lock.json" "$expected/nix/packages/difit/package-lock.json" || return 1
  assert_same_mode "$WORK/nix/packages/difit/package-lock.json" "$expected/nix/packages/difit/package-lock.json" || return 1
  cmp -s "$WORK/nix/packages/shellfirm/Cargo.lock" "$expected/nix/packages/shellfirm/Cargo.lock" || return 1
  assert_same_mode "$WORK/nix/packages/shellfirm/Cargo.lock" "$expected/nix/packages/shellfirm/Cargo.lock" || return 1
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

file_identity() {
  python3 - "$1" <<'PY'
import os
import stat
import sys

value = os.stat(sys.argv[1])
print(value.st_ino, value.st_mtime_ns, stat.S_IMODE(value.st_mode), value.st_size)
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

flake_lock_ref() {
  local input=$1 node
  node=$(jq -r --arg input "$input" '.nodes[.root].inputs[$input]' "$WORK/flake.lock")
  jq -r --arg node "$node" '.nodes[$node].original.ref' "$WORK/flake.lock"
}

report_section() {
  local heading=$1
  awk -v heading="$heading" '
    $0 == heading { inside = 1; next }
    inside && /^  / { print; next }
    inside { exit }
  ' <<<"$output"
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
  [[ "$output" == *"Usage: update-pins [--retry <MAX_ATTEMPTS>] [--force] [target]"* ]]
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

@test "retry attempts are bounded and malformed options have no side effects" {
  original="$WORK/original"
  save_managed "$original"

  run_update_pins --retry 0
  [ "$status" -eq 2 ]
  [[ "$output" == *"--retry must be an integer from 1 to 5, got '0'"* ]]
  run_update_pins --retry 6
  [ "$status" -eq 2 ]
  [[ "$output" == *"--retry must be an integer from 1 to 5, got '6'"* ]]
  run_update_pins --retry many
  [ "$status" -eq 2 ]
  [[ "$output" == *"--retry must be an integer from 1 to 5, got 'many'"* ]]
  run_update_pins --retry
  [ "$status" -eq 2 ]
  [[ "$output" == *"--retry requires a maximum attempt count"* ]]
  run_update_pins --retry=
  [ "$status" -eq 2 ]
  [[ "$output" == *"--retry must be an integer from 1 to 5, got ''"* ]]
  run_update_pins --unknown
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown option '--unknown'"* ]]
  [ ! -e "$UPDATE_PINS_COMMAND_LOG" ]
  assert_managed_matches "$original"
}

@test "force refreshes and re-pins a changed same-version Codex artifact" {
  fixed_hash=sha256-V95M9AFEvffQABDy9VV6fWQsK5cFMJv63hZ90xPiypM=
  original="$WORK/original"
  save_managed "$original"
  original_version=$(jq -r .version "$WORK/nix/pins/codex-app.json")
  original_url=$(jq -r .url "$WORK/nix/pins/codex-app.json")

  run_update_pins codex-app --force --retry=5

  [ "$status" -eq 0 ]
  [[ "$output" == *"codex-app updated."* ]]
  section=$(report_section "Applied changes:")
  [ "$section" = $'  codex-app:\n    - app hash: changed' ]
  [[ "$output" != *"$fixed_hash"* ]]
  [[ "$output" != *"Rolled back candidate changes:"* ]]
  [ "$(jq -r .version "$WORK/nix/pins/codex-app.json")" = "$original_version" ]
  [ "$(jq -r .url "$WORK/nix/pins/codex-app.json")" = "$original_url" ]
  [ "$(jq -r .hash "$WORK/nix/pins/codex-app.json")" = "$fixed_hash" ]
  [ "$(grep -c '^curl ' "$UPDATE_PINS_COMMAND_LOG")" -eq 2 ]
  grep -Fq "https://persistent.oaistatic.com/codex-app-prod/appcast.xml" "$UPDATE_PINS_COMMAND_LOG"
  grep -Fq "$(jq -r .url "$WORK/nix/pins/codex-app.json")" "$UPDATE_PINS_COMMAND_LOG"
  grep -Eq '^nix store prefetch-file --json --name update-pins-.+\.zip file:///.*/update-pins-fetch-.+\.zip$' "$UPDATE_PINS_COMMAND_LOG"
  [ ! -e "$UPDATE_PINS_FLAKE_UPDATE_LOG" ]
  cp "$WORK/nix/pins/codex-app.json" "$original/nix/pins/codex-app.json"
  assert_managed_matches "$original"
}

@test "same-version paired force refreshes assets without flake input churn" {
  fixed_hash=sha256-1ZOG4K5DXikvvg6825VLde1fs5IgkSd8sZ95j8XVBxg=
  jq --arg hash "$fixed_hash" '.assets[].hash = $hash' "$WORK/nix/pins/hcom.json" >"$WORK/hcom.json"
  mv "$WORK/hcom.json" "$WORK/nix/pins/hcom.json"
  git -C "$WORK" add nix/pins/hcom.json
  git -C "$WORK" commit -q -m "fixed hcom hash fixture"
  original="$WORK/original"
  save_managed "$original"

  run_update_pins --force hcom

  [ "$status" -eq 0 ]
  [[ "$output" == *"hcom is up to date."* ]]
  [[ "$output" != *"Applied changes:"* ]]
  [[ "$output" != *"Rolled back candidate changes:"* ]]
  grep -Fq "gh api --include repos/aannoo/hcom/releases/latest" "$UPDATE_PINS_COMMAND_LOG"
  asset_count=$(jq '.assets | length' "$WORK/nix/pins/hcom.json")
  [ "$(grep -c '^curl .*github.com/aannoo/hcom/releases/download/' "$UPDATE_PINS_COMMAND_LOG")" -eq "$asset_count" ]
  [ "$(grep '^curl .*github.com/aannoo/hcom/releases/download/' "$UPDATE_PINS_COMMAND_LOG" | awk '{print $NF}' | sort -u | wc -l)" -eq "$asset_count" ]
  [ "$(grep -c '^nix store prefetch-file' "$UPDATE_PINS_COMMAND_LOG")" -eq "$asset_count" ]
  ! grep -Fq "nix flake update" "$UPDATE_PINS_COMMAND_LOG"
  [ ! -e "$UPDATE_PINS_FLAKE_UPDATE_LOG" ]
  assert_managed_matches "$original"
}

@test "same-version shellfirm force validates without writing" {
  original="$WORK/original"
  save_managed "$original"
  pin_before=$(file_identity "$WORK/nix/pins/shellfirm.json")
  lock_before=$(file_identity "$WORK/nix/packages/shellfirm/Cargo.lock")
  export UPDATE_PINS_SOURCE_HASH
  UPDATE_PINS_SOURCE_HASH=$(jq -r .srcHash "$WORK/nix/pins/shellfirm.json")
  export UPDATE_PINS_SHELLFIRM_REUSE_LOCK=1
  export UPDATE_PINS_SHELLFIRM_BUILD_MODE=success

  run_update_pins --force shellfirm

  [ "$status" -eq 0 ]
  [[ "$output" == *"shellfirm: candidate source and lockfile are unchanged"* ]]
  [[ "$output" == *"shellfirm is up to date."* ]]
  [[ "$output" != *"Applied changes:"* ]]
  [ "$(cat "$UPDATE_PINS_SHELLFIRM_BUILD_COUNT")" -eq 1 ]
  [ "$(file_identity "$WORK/nix/pins/shellfirm.json")" = "$pin_before" ]
  [ "$(file_identity "$WORK/nix/packages/shellfirm/Cargo.lock")" = "$lock_before" ]
  assert_managed_matches "$original"
}

@test "same-version difit force validates without writing" {
  original="$WORK/original"
  save_managed "$original"
  pin_before=$(file_identity "$WORK/nix/pins/difit.json")
  lock_before=$(file_identity "$WORK/nix/packages/difit/package-lock.json")
  export UPDATE_PINS_DIFIT_SOURCE_HASH
  UPDATE_PINS_DIFIT_SOURCE_HASH=$(jq -r .srcHash "$WORK/nix/pins/difit.json")
  export UPDATE_PINS_DIFIT_REUSE_LOCK=1
  export UPDATE_PINS_REFRESHED_NPM_HASH
  UPDATE_PINS_REFRESHED_NPM_HASH=$(jq -r .npmDepsHash "$WORK/nix/pins/difit.json")
  export UPDATE_PINS_DIFIT_BUILD_MODE=verify-existing

  run_update_pins --force difit

  [ "$status" -eq 0 ]
  [[ "$output" == *"difit: candidate source and lockfile are unchanged"* ]]
  [[ "$output" == *"difit is up to date."* ]]
  [[ "$output" != *"Applied changes:"* ]]
  [ "$(cat "$UPDATE_PINS_DIFIT_BUILD_COUNT")" -eq 2 ]
  [ ! -e "$UPDATE_PINS_FLAKE_UPDATE_LOG" ]
  [ "$(file_identity "$WORK/nix/pins/difit.json")" = "$pin_before" ]
  [ "$(file_identity "$WORK/nix/packages/difit/package-lock.json")" = "$lock_before" ]
  assert_managed_matches "$original"
}

@test "same-version shellfirm force updates only a changed upstream lockfile" {
  original="$WORK/original"
  save_managed "$original"
  export UPDATE_PINS_SOURCE_HASH
  UPDATE_PINS_SOURCE_HASH=$(jq -r .srcHash "$WORK/nix/pins/shellfirm.json")
  export UPDATE_PINS_SHELLFIRM_BUILD_MODE=success

  run_update_pins --force shellfirm

  [ "$status" -eq 0 ]
  [[ "$output" == *"shellfirm updated."* ]]
  grep -Fq 'name = "shellfirm"' "$WORK/nix/packages/shellfirm/Cargo.lock"
  section=$(report_section "Applied changes:")
  [ "$section" = $'  shellfirm:\n    - lockfile [nix/packages/shellfirm/Cargo.lock]: changed' ]
  [ "$(cat "$UPDATE_PINS_SHELLFIRM_BUILD_COUNT")" -eq 1 ]
  cp "$WORK/nix/packages/shellfirm/Cargo.lock" "$original/nix/packages/shellfirm/Cargo.lock"
  assert_managed_matches "$original"
}

@test "one-attempt force refresh reaches the local prefetch without an implicit retry" {
  original="$WORK/original"
  save_managed "$original"
  export UPDATE_PINS_SCHEMA_HASH
  UPDATE_PINS_SCHEMA_HASH=$(jq -r .hash "$WORK/nix/pins/claude-code-settings-schema.json")

  run_update_pins --retry 1 --force claude-code-settings-schema

  [ "$status" -eq 0 ]
  [[ "$output" != *"Applied changes:"* ]]
  [[ "$output" != *"Rolled back candidate changes:"* ]]
  [ "$(grep -c '^curl ' "$UPDATE_PINS_COMMAND_LOG")" -eq 1 ]
  grep -Eq '^nix store prefetch-file --json --name update-pins-.+\.json file:///.*/update-pins-fetch-.+\.json$' "$UPDATE_PINS_COMMAND_LOG"
  assert_managed_matches "$original"
}

@test "transient fetch failures recover at the default bound with fresh files" {
  original="$WORK/original"
  save_managed "$original"
  export UPDATE_PINS_SCHEMA_HASH
  UPDATE_PINS_SCHEMA_HASH=$(jq -r .hash "$WORK/nix/pins/claude-code-settings-schema.json")
  export UPDATE_PINS_CURL_FAIL_PATTERN=json.schemastore.org
  export UPDATE_PINS_CURL_FAIL_COUNT=2

  run_update_pins claude-code-settings-schema

  [ "$status" -eq 0 ]
  [[ "$output" == *"retrying attempt 2/3"* ]]
  [[ "$output" == *"retrying attempt 3/3"* ]]
  [ "$(grep -c '^curl ' "$UPDATE_PINS_COMMAND_LOG")" -eq 3 ]
  [ "$(sed -n 's/.* --output \([^ ]*\) --write-out.*/\1/p' "$UPDATE_PINS_COMMAND_LOG" | sort -u | wc -l)" -eq 3 ]
  assert_managed_matches "$original"
}

@test "permanent HTTP failure is attempted once and rolls back" {
  original="$WORK/original"
  save_managed "$original"
  export UPDATE_PINS_CURL_FAIL_PATTERN=json.schemastore.org
  export UPDATE_PINS_CURL_FAIL_COUNT=5
  export UPDATE_PINS_CURL_FAIL_HTTP_STATUS=404

  run_update_pins claude-code-settings-schema

  [ "$status" -eq 1 ]
  [[ "$output" == *"HTTP 404"* ]]
  [[ "$output" != *"retrying attempt"* ]]
  [ "$(grep -c '^curl ' "$UPDATE_PINS_COMMAND_LOG")" -eq 1 ]
  assert_managed_matches "$original"
}

@test "all runs every target in registry order and reports a no-op" {
  original="$WORK/original"
  save_managed "$original"
  make_unrelated_updates_noop

  run_update_pins

  [ "$status" -eq 0 ]
  headers="$(printf '%s\n' "$output" | sed -n 's/^== //p')"
  [ "$headers" = $'hcom\nagent-slack\nagent-browser\nwatchexec\nshellfirm\nherdr\ndifit\nclaude-code-settings-schema\ncodex-app' ]
  [ "$(printf '%s\n' "$output" | tail -n 1)" = "All pins up to date." ]
  [[ "$output" != *"Applied changes:"* ]]
  [[ "$output" != *"Rolled back candidate changes:"* ]]
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
  [ "$(jq -r .srcHash "$WORK/nix/pins/herdr.json")" = "sha256-JaZjQmPBsfb8RpegTiuZBOpLBCqJr1nck+wfXUSEiiY=" ]
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
  [ "$(jq -r '.assets["x86_64-linux"].hash' "$WORK/nix/pins/hcom.json")" = "sha256-1ZOG4K5DXikvvg6825VLde1fs5IgkSd8sZ95j8XVBxg=" ]
  grep -Fq 'url = "github:aannoo/hcom/v9.9.9";' "$WORK/flake.nix"
  [ "$(flake_lock_ref hcom-src)" = "v9.9.9" ]
  grep -Fq "gh api --include repos/aannoo/hcom/releases/latest" "$UPDATE_PINS_COMMAND_LOG"
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
  [ "$(jq -r '.assets["x86_64-linux"].hash' "$WORK/nix/pins/agent-slack.json")" = "sha256-1ZOG4K5DXikvvg6825VLde1fs5IgkSd8sZ95j8XVBxg=" ]
  grep -Fq 'url = "github:stablyai/agent-slack/v9.9.9";' "$WORK/flake.nix"
  [ "$(flake_lock_ref agent-slack-skill)" = "v9.9.9" ]
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
  [ "$(jq -r .srcHash "$WORK/nix/pins/shellfirm.json")" = "sha256-JaZjQmPBsfb8RpegTiuZBOpLBCqJr1nck+wfXUSEiiY=" ]
  jq -e 'keys == ["srcHash", "version"]' "$WORK/nix/pins/shellfirm.json"
  grep -Fq 'version = "9.9.9"' "$WORK/nix/packages/shellfirm/Cargo.lock"
  [ "$(cat "$UPDATE_PINS_SHELLFIRM_BUILD_COUNT")" -eq 1 ]
  section=$(report_section "Applied changes:")
  [ "$section" = $'  shellfirm:\n    - version: 0.3.10 -> 9.9.9\n    - source hash: changed\n    - lockfile [nix/packages/shellfirm/Cargo.lock]: changed' ]
  cp "$WORK/nix/pins/shellfirm.json" "$original/nix/pins/shellfirm.json"
  cp "$WORK/nix/packages/shellfirm/Cargo.lock" "$original/nix/packages/shellfirm/Cargo.lock"
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
  export UPDATE_PINS_SCHEMA_HASH=sha256-3wrW5DiA8JyQ6/lfGREBeKumiQ3wAQ69p0hQKeK1Q7Q=

  run_update_pins claude-code-settings-schema

  [ "$status" -eq 0 ]
  [ "$(jq -r .hash "$WORK/nix/pins/claude-code-settings-schema.json")" = "sha256-3wrW5DiA8JyQ6/lfGREBeKumiQ3wAQ69p0hQKeK1Q7Q=" ]
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

@test "single target ignores an unrelated dirty pin" {
  printf '{"dirty":true}\n' >"$WORK/nix/pins/hcom.json"
  original="$WORK/original"
  save_managed "$original"

  run_update_pins herdr

  [ "$status" -eq 0 ]
  [[ "$output" == *"herdr is up to date."* ]]
  assert_managed_matches "$original"
}

@test "all validates every pin before the first upstream command" {
  jq '.hash = "invalid"' "$WORK/nix/pins/codex-app.json" >"$WORK/codex-app.json"
  mv "$WORK/codex-app.json" "$WORK/nix/pins/codex-app.json"
  git -C "$WORK" add nix/pins/codex-app.json
  git -C "$WORK" commit -q -m "malformed codex pin fixture"
  original="$WORK/original"
  save_managed "$original"

  run_update_pins

  [ "$status" -eq 1 ]
  [[ "$output" == *"codex-app: nix/pins/codex-app.json: hash"* ]]
  [ ! -e "$UPDATE_PINS_COMMAND_LOG" ]
  assert_managed_matches "$original"
}

@test "same-version malformed release pin fails before discovery" {
  jq '.assets["x86_64-linux"].hash = null' "$WORK/nix/pins/herdr.json" >"$WORK/herdr.json"
  mv "$WORK/herdr.json" "$WORK/nix/pins/herdr.json"
  git -C "$WORK" add nix/pins/herdr.json
  git -C "$WORK" commit -q -m "malformed herdr pin fixture"
  original="$WORK/original"
  save_managed "$original"

  run_update_pins herdr

  [ "$status" -eq 1 ]
  [[ "$output" == *"herdr: nix/pins/herdr.json: assets.x86_64-linux.hash"* ]]
  [ ! -e "$UPDATE_PINS_COMMAND_LOG" ]
  assert_managed_matches "$original"
}

@test "invalid fetched asset hash rolls back without publishing a candidate" {
  original="$WORK/original"
  save_managed "$original"
  export UPDATE_PINS_HERDR_TAG=v9.9.9
  export UPDATE_PINS_ASSET_HASH=invalid

  run_update_pins herdr

  [ "$status" -eq 1 ]
  [[ "$output" == *"herdr: nix/pins/herdr.json: assets."*".hash: expected a sha256 SRI hash"* ]]
  assert_managed_matches "$original"
  assert_no_staging_files
}

@test "release pin rejects missing and extra asset platforms before discovery" {
  for mutation in 'del(.assets["x86_64-linux"])' '.assets.extra = .assets["aarch64-linux"]'; do
    jq "$mutation" "$WORK/nix/pins/herdr.json" >"$WORK/herdr.json"
    mv "$WORK/herdr.json" "$WORK/nix/pins/herdr.json"
    git -C "$WORK" add nix/pins/herdr.json
    git -C "$WORK" commit -q -m "malformed herdr platform fixture"

    run_update_pins herdr

    [ "$status" -eq 1 ]
    [[ "$output" == *"herdr: nix/pins/herdr.json: assets: expected systems"* ]]
    [ ! -e "$UPDATE_PINS_COMMAND_LOG" ]

    git -C "$WORK" reset -q --hard HEAD^
  done
}

@test "ordinary release rejects an unsafe candidate version before prefetch" {
  original="$WORK/original"
  save_managed "$original"
  export UPDATE_PINS_HERDR_TAG='v9.9.9"; builtins.abort "unsafe'

  run_update_pins herdr

  [ "$status" -eq 1 ]
  [[ "$output" == *"herdr: unsupported release version"* ]]
  ! grep -Fq "store prefetch-file" "$UPDATE_PINS_COMMAND_LOG"
  assert_managed_matches "$original"
}

@test "postflight validation failure rolls back the completed target" {
  original="$WORK/original"
  save_managed "$original"
  export UPDATE_PINS_HCOM_TAG=v9.9.9
  export UPDATE_PINS_CORRUPT_FLAKE_AFTER_UPDATE=hcom-src

  run_update_pins hcom

  [ "$status" -eq 1 ]
  [[ "$output" == *"expected one tagged flake input URL"* ]]
  [[ "$output" == *"update-pins: failed; restoring managed files from backup"* ]]
  [[ "$output" != *"Applied changes:"* ]]
  section=$(report_section "Rolled back candidate changes:")
  [ "$(printf '%s\n' "$section" | sed -n 's/^  \([^ ].*\):$/\1/p')" = "hcom" ]
  assert_managed_matches "$original"
  assert_no_staging_files
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

  run_update_pins --retry 5

  [ "$status" -ne 0 ]
  [ "$(wc -l <"$UPDATE_PINS_FLAKE_UPDATE_LOG")" -eq 1 ]
  [[ "$output" != *"retrying attempt"* ]]
  [[ "$output" != *"Applied changes:"* ]]
  [[ "$output" == *"Rolled back candidate changes:"* ]]
  assert_managed_matches "$original"
  assert_no_staging_files
}

@test "after-state read failure aborts and restores a successful target" {
  original="$WORK/original"
  save_managed "$original"
  export UPDATE_PINS_HCOM_TAG=v9.9.9
  export UPDATE_PINS_DELETE_FLAKE_AFTER_UPDATE=hcom-src

  run_update_pins hcom

  [ "$status" -ne 0 ]
  [[ "$output" == *"failed to access"* ]]
  [[ "$output" != *"Applied changes:"* ]]
  [[ "$output" != *"Rolled back candidate changes:"* ]]
  [[ "$output" != *"secret-before-commit"* ]]
  assert_managed_matches "$original"
  assert_no_staging_files
}

@test "rollback failure retains the update error and suppresses success status" {
  export UPDATE_PINS_HCOM_TAG=v9.9.9
  export UPDATE_PINS_BREAK_ROLLBACK=hcom-src

  run_update_pins hcom

  [ "$status" -ne 0 ]
  [[ "$output" == *"flake update failed before rollback"* ]]
  [[ "$output" == *"rollback also failed"* ]]
  [[ "$output" != *"Applied changes:"* ]]
  [[ "$output" != *"Rolled back candidate changes:"* ]]
  [ -d "$WORK/flake.lock" ]
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

@test "invalid fetched metadata is not retried" {
  original="$WORK/original"
  save_managed "$original"
  export UPDATE_PINS_INVALID_NPM_JSON=1

  run_update_pins difit

  [ "$status" -eq 1 ]
  [[ "$output" == *"returned invalid JSON"* ]]
  [ "$(grep -c 'registry.npmjs.org/difit/latest' "$UPDATE_PINS_COMMAND_LOG")" -eq 1 ]
  [[ "$output" != *"retrying attempt"* ]]
  assert_managed_matches "$original"
}

@test "difit version bump updates pin, lockfile, and flake input" {
  original="$WORK/original"
  save_managed "$original"
  export UPDATE_PINS_DIFIT_VERSION=9.9.9
  export UPDATE_PINS_DIFIT_BUILD_MODE=success
  make_difit_tarball "$UPDATE_PINS_DIFIT_VERSION"

  run_update_pins difit

  [ "$status" -eq 0 ]
  [ "$(jq -r .srcHash "$WORK/nix/pins/difit.json")" = "sha256-gmer9Ei3Jq/YwFQ13VuGqxjSZiafe7wWoJnabLgSrKE=" ]
  [ "$(jq -r .npmDepsHash "$WORK/nix/pins/difit.json")" = "sha256-32X0K6wkLW2x9cJJJ6J+cu5HOM2+oTZe5AEqLRHvpPM=" ]
  [ "$(jq -r .version "$WORK/nix/packages/difit/package-lock.json")" = "9.9.9" ]
  [ "$(jq -r '.packages[""].version' "$WORK/nix/packages/difit/package-lock.json")" = "9.9.9" ]
  grep -Fq 'url = "github:yoshiko-pg/difit/v9.9.9";' "$WORK/flake.nix"
  [ "$(flake_lock_ref difit-src)" = "v9.9.9" ]
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

@test "npm install failure is not retried" {
  original="$WORK/original"
  save_managed "$original"
  export UPDATE_PINS_DIFIT_VERSION=9.9.9
  export UPDATE_PINS_FAIL_NPM_INSTALL=1
  make_difit_tarball "$UPDATE_PINS_DIFIT_VERSION"

  run_update_pins --retry 5 difit

  [ "$status" -eq 1 ]
  [[ "$output" == *"npm install failed"* ]]
  [ "$(grep -c '^npm install ' "$UPDATE_PINS_COMMAND_LOG")" -eq 1 ]
  [[ "$output" != *"retrying attempt"* ]]
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
  [ "$(jq -r '.assets["x86_64-linux"].hash' "$WORK/nix/pins/agent-browser.json")" = "sha256-1ZOG4K5DXikvvg6825VLde1fs5IgkSd8sZ95j8XVBxg=" ]
  grep -Fq 'url = "github:vercel-labs/agent-browser/v9.9.9";' "$WORK/flake.nix"
  [ "$(flake_lock_ref agent-browser-skill)" = "v9.9.9" ]
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
  [ "$(jq -r '.assets["aarch64-darwin"].hash' "$WORK/nix/pins/watchexec.json")" = "sha256-1ZOG4K5DXikvvg6825VLde1fs5IgkSd8sZ95j8XVBxg=" ]
  [ "$(jq -r '.assets["x86_64-darwin"].hash' "$WORK/nix/pins/watchexec.json")" = "sha256-1ZOG4K5DXikvvg6825VLde1fs5IgkSd8sZ95j8XVBxg=" ]
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
  [[ "$output" == *"watchexec: artifact download: curl failed with status 7"* ]]
  [ "$(grep -c "$UPDATE_PINS_FAIL_WATCHEXEC_TARGET" "$UPDATE_PINS_COMMAND_LOG")" -eq 3 ]
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
  [ "$(jq -r .hash "$WORK/nix/pins/codex-app.json")" = "sha256-V95M9AFEvffQABDy9VV6fWQsK5cFMJv63hZ90xPiypM=" ]
  [ "$(jq -r .appName "$WORK/nix/pins/codex-app.json")" = "ChatGPT.app" ]
  [ "$(jq -r .bundleIdentifier "$WORK/nix/pins/codex-app.json")" = "com.openai.codex" ]
  [ "$(jq -r .displayName "$WORK/nix/pins/codex-app.json")" = "ChatGPT" ]
  cp "$WORK/nix/pins/codex-app.json" "$original/nix/pins/codex-app.json"
  assert_managed_matches "$original"
}

@test "codex app up to date skips prefetch and leaves managed files unchanged" {
  original="$WORK/original"
  save_managed "$original"

  run_update_pins codex-app

  [ "$status" -eq 0 ]
  [[ "$output" == *"codex-app: $(jq -r .version "$WORK/nix/pins/codex-app.json") (up to date)"* ]]
  grep -Fq "https://persistent.oaistatic.com/codex-app-prod/appcast.xml" "$UPDATE_PINS_COMMAND_LOG"
  ! grep -q '^nix ' "$UPDATE_PINS_COMMAND_LOG"
  assert_managed_matches "$original"
}

@test "codex app update rejects an appcast and bundle version mismatch" {
  original="$WORK/original"
  save_managed "$original"
  export UPDATE_PINS_CODEX_APP_VERSION=26.999.10101
  export UPDATE_PINS_CODEX_APP_URL=https://persistent.oaistatic.com/codex-app-prod/ChatGPT-darwin-arm64-26.999.10101.zip
  export UPDATE_PINS_CODEX_APP_BUNDLE_VERSION=26.999.10100

  run_update_pins codex-app

  [ "$status" -ne 0 ]
  [[ "$output" == *"appcast version 26.999.10101 did not match bundle version 26.999.10100"* ]]
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
  [[ "$output" != *"Applied changes:"* ]]
  section=$(report_section "Rolled back candidate changes:")
  targets=$(printf '%s\n' "$section" | sed -n 's/^  \([^ ].*\):$/\1/p')
  [ "$targets" = $'hcom\nagent-slack' ]
  assert_managed_matches "$original"
}

@test "codex app late failure restores a change from an earlier target" {
  original="$WORK/original"
  save_managed "$original"
  make_unrelated_updates_noop
  export UPDATE_PINS_HCOM_TAG=v1.2.3
  export UPDATE_PINS_CODEX_APP_VERSION=26.999.10101
  export UPDATE_PINS_CODEX_APP_URL=https://persistent.oaistatic.com/codex-app-prod/ChatGPT-darwin-arm64-26.999.10101.zip
  export UPDATE_PINS_CODEX_APP_BUNDLE_VERSION=26.999.10102

  run_update_pins

  [ "$status" -eq 1 ]
  [[ "$output" == *"== codex-app"* ]]
  [[ "$output" == *"update-pins: failed; restoring managed files from backup"* ]]
  [[ "$output" != *"Pins updated."* ]]
  [[ "$output" != *"All pins up to date."* ]]
  [[ "$output" != *"Applied changes:"* ]]
  section=$(report_section "Rolled back candidate changes:")
  [ "$(printf '%s\n' "$section" | sed -n 's/^  \([^ ].*\):$/\1/p')" = "hcom" ]
  assert_managed_matches "$original"
  assert_no_staging_files
}

@test "shellfirm rejects a missing upstream lockfile before mutation" {
  original="$WORK/original"
  save_managed "$original"
  export UPDATE_PINS_SHELLFIRM_TAG=v8.8.8
  export UPDATE_PINS_SHELLFIRM_LOCK_MODE=missing

  run_update_pins shellfirm

  [ "$status" -ne 0 ]
  [[ "$output" == *"expected exactly one directory containing regular Cargo.toml and Cargo.lock files, found 0"* ]]
  [ ! -e "$UPDATE_PINS_SHELLFIRM_BUILD_COUNT" ]
  assert_managed_matches "$original"
}

@test "shellfirm rejects a mismatched lockfile root version before mutation" {
  original="$WORK/original"
  save_managed "$original"
  export UPDATE_PINS_SHELLFIRM_TAG=v8.8.8
  export UPDATE_PINS_SHELLFIRM_LOCK_MODE=version-mismatch

  run_update_pins shellfirm

  [ "$status" -ne 0 ]
  [[ "$output" == *"expected exactly one source-free shellfirm 8.8.8 package, found 1 shellfirm roots"* ]]
  [ ! -e "$UPDATE_PINS_SHELLFIRM_BUILD_COUNT" ]
  assert_managed_matches "$original"
}

@test "shellfirm rejects a git dependency before mutation" {
  original="$WORK/original"
  save_managed "$original"
  export UPDATE_PINS_SHELLFIRM_TAG=v8.8.8
  export UPDATE_PINS_SHELLFIRM_LOCK_MODE=git-dependency

  run_update_pins shellfirm

  [ "$status" -ne 0 ]
  [[ "$output" == *"git dependency is unsupported: git-fixture 1.0.0"* ]]
  [ ! -e "$UPDATE_PINS_SHELLFIRM_BUILD_COUNT" ]
  assert_managed_matches "$original"
}

@test "shellfirm rejects an unsupported registry before mutation" {
  original="$WORK/original"
  save_managed "$original"
  export UPDATE_PINS_SHELLFIRM_TAG=v8.8.8
  export UPDATE_PINS_SHELLFIRM_LOCK_MODE=alternate-registry

  run_update_pins shellfirm

  [ "$status" -ne 0 ]
  [[ "$output" == *"unsupported dependency source for fixture-dependency 1.0.0"* ]]
  [ ! -e "$UPDATE_PINS_SHELLFIRM_BUILD_COUNT" ]
  assert_managed_matches "$original"
}

@test "shellfirm late package build failure restores its pin and lockfile" {
  original="$WORK/original"
  save_managed "$original"
  export UPDATE_PINS_SHELLFIRM_TAG=v8.8.8
  export UPDATE_PINS_SHELLFIRM_BUILD_MODE=fails

  run_update_pins --retry 5 shellfirm

  [ "$status" -ne 0 ]
  [[ "$output" == *"shellfirm: candidate package build failed with status 1"* ]]
  [ "$(cat "$UPDATE_PINS_SHELLFIRM_BUILD_COUNT")" -eq 1 ]
  [[ "$output" != *"retrying attempt"* ]]
  [[ "$output" != *"Applied changes:"* ]]
  section=$(report_section "Rolled back candidate changes:")
  [ "$section" = $'  shellfirm:\n    - version: 0.3.10 -> 8.8.8\n    - source hash: changed\n    - lockfile [nix/packages/shellfirm/Cargo.lock]: changed' ]
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
  [[ "$output" == *"herdr: artifact download: curl failed with status 7"* ]]
  [ "$(grep -c "github.com/ogulcancelik/herdr/archive/refs/tags/" "$UPDATE_PINS_COMMAND_LOG")" -eq 3 ]
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
  [ "$(jq -r '.assets["aarch64-darwin"].hash' "$WORK/nix/pins/hcom.json")" = "sha256-1ZOG4K5DXikvvg6825VLde1fs5IgkSd8sZ95j8XVBxg=" ]
  grep -Fq 'url = "github:stablyai/agent-slack/v4.5.6";' "$WORK/flake.nix"
  [ "$(jq -r .version "$WORK/nix/pins/shellfirm.json")" = "8.8.8" ]
  [ "$(jq -r .srcHash "$WORK/nix/pins/shellfirm.json")" = "sha256-JaZjQmPBsfb8RpegTiuZBOpLBCqJr1nck+wfXUSEiiY=" ]
  jq -e 'keys == ["srcHash", "version"]' "$WORK/nix/pins/shellfirm.json"
  grep -Fq 'version = "8.8.8"' "$WORK/nix/packages/shellfirm/Cargo.lock"
  [ "$(cat "$UPDATE_PINS_SHELLFIRM_BUILD_COUNT")" -eq 1 ]
  [ "$(jq -r .version "$WORK/nix/pins/herdr.json")" = "9.9.9" ]
  [ "$(jq -r .srcHash "$WORK/nix/pins/herdr.json")" = "sha256-JaZjQmPBsfb8RpegTiuZBOpLBCqJr1nck+wfXUSEiiY=" ]
  [ "$(jq -r '.assets["x86_64-linux"].hash' "$WORK/nix/pins/herdr.json")" = "sha256-1ZOG4K5DXikvvg6825VLde1fs5IgkSd8sZ95j8XVBxg=" ]
  [ "$(jq -r .hash "$WORK/nix/pins/claude-code-settings-schema.json")" = "sha256-3wrW5DiA8JyQ6/lfGREBeKumiQ3wAQ69p0hQKeK1Q7Q=" ]
  [ "$(flake_lock_ref hcom-src)" = "v1.2.3" ]
  [ "$(flake_lock_ref agent-slack-skill)" = "v4.5.6" ]
  [ "$(cat "$UPDATE_PINS_FLAKE_UPDATE_LOG")" = $'hcom-src\nagent-slack-skill' ]
  [ "$(printf '%s\n' "$output" | grep -c '^Applied changes:$')" -eq 1 ]
  section=$(report_section "Applied changes:")
  targets=$(printf '%s\n' "$section" | sed -n 's/^  \([^ ].*\):$/\1/p')
  [ "$targets" = $'hcom\nagent-slack\nshellfirm\nherdr\nclaude-code-settings-schema' ]
  [[ "$section" != *"sha256-"* ]]
  [[ "$output" != *"Rolled back candidate changes:"* ]]
  [[ "$output" != *"secret-before-commit"* ]]
  [ "$(printf '%s\n' "$output" | tail -n 1)" = "Pins updated. Review with 'git diff', verify with 'nix run .#build', then commit." ]
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
  git -C "$WORK" add flake.nix flake.lock nix/packages/difit/package-lock.json nix/packages/shellfirm/Cargo.lock nix/pins/*.json
  git -C "$WORK" commit -q -m "apply first update"

  run_update_pins

  [ "$status" -eq 0 ]
  [[ "$output" == *"All pins up to date."* ]]
  [[ "$output" != *"Applied changes:"* ]]
  [[ "$output" != *"Rolled back candidate changes:"* ]]
  assert_managed_matches "$after_first"
}
