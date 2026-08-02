#!/usr/bin/env bats
# Nix-built public binary, real Git transactions, and real child-process argv
# remain here. Removed Bats assertions map to these narrower Rust assertions:
# - CLI/jobs/retry: cli::compatible_parser_*, policy::*_policy_*, and
#   fetch::transient_* assert exact values, bounds, attempts, and fresh files;
#   the public exit contract remains in test 1.
# - target selection/order/report: engine::all_runs_*, engine::all_preflights_*,
#   and ledger::rendering_* assert registry execution and field order.
# - production no-op/rerun: targets::production_dispatch_* invokes every
#   registry target twice and asserts stable bytes, modes, and bounded metadata
#   child programs without duplicating the target inventory here.
# - preflight/postflight: engine::failed_all_target_preflight_* asserts that no
#   updater runs after a preflight failure, while engine::all_preflights_*
#   asserts the full validate/update/validate sequence; the Hcom and Shellfirm
#   process tests retain public check and rollback reporting.
# - transaction/dirty/mode/untracked/lock: transaction::dirty_*,
#   scoped_transaction_*, rollback_*, concurrent_transaction_*, and
#   identical_write_* assert bytes, permissions, ownership, lock release,
#   restore+unlock error retention, and inode/mtime stability; the Hcom process
#   test retains the real process boundary.
# - flake input update: targets::paired_flake_version_* asserts byte-preserving
#   source replacement and mutating_commands_* asserts bounded argv; the Difit
#   and Agent Browser tests retain real `nix flake update` argv and publication.
# - release/multi-asset: targets::asset_jobs_* and asset_batch_failure_* assert
#   reverse-completion ordering, bounded concurrency, and no partial pin
#   publication; the Agent Browser test retains a paired multi-asset E2E.
# - Shellfirm source/hash/lock: shellfirm::validates_*, rejects_*, reads_one_*,
#   build::diagnostics_*, and the engine rollback tests assert validation,
#   bounded diagnostics, and restoration; the Shellfirm process tests retain
#   successful four-file synchronization, rule diffs, and policy rollback.
# - Difit source/pnpm/build: targets::npm_archive_*/validates_npm_* and
#   build::parses_*/rejects_*/candidate_build_* assert archive identity,
#   key/hash extraction, one mismatch candidate, and bounded final diagnostics;
#   fetch::transient_* supplies retry bounds and the process test retains real
#   child order.
# - Codex archive identity: codex_app::appcast_* and bundle_identity_* assert
#   appName, bundle ID, display name, version, URL/archive identity, and unsafe
#   ZIP rejection; the Codex process test retains real ZIP success.
# - all-target rollback/idempotence: engine::late_target_failure_* and
#   all_preflights_* assert real-Git all-managed rollback, shared flake.lock
#   restore, commit-only success, and second-run inode/mtime stability.

source "$BATS_TEST_DIRNAME/test-helper.bash"

MANAGED_PIN_NAMES=(
  agent-browser
  codex-app
  difit
  hcom
  shellfirm
)

make_difit_tarball() {
  local version=$1
  mkdir -p "$WORK/difit-tar/package"
  cat >"$WORK/difit-tar/package/package.json" <<JSON
{
  "name": "difit",
  "version": "$version",
  "packageManager": "pnpm@11.6.0"
}
JSON
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
  require_nix_fixture UPDATE_PINS_TEST_BIN "built update-pins binary"

  REPO_ROOT="$(git rev-parse --show-toplevel)"
  BASH_BIN="$(command -v bash)"
  WORK="$(mktemp -d)"
  mkdir -p "$WORK/nix/pins" "$WORK/nix/packages/shellfirm" \
    "$WORK/nix/packages/agent-command-guard"
  for pin_name in "${MANAGED_PIN_NAMES[@]}"; do
    cp "$REPO_ROOT/nix/pins/$pin_name.json" "$WORK/nix/pins/$pin_name.json"
  done
  cp "$REPO_ROOT/nix/packages/shellfirm/Cargo.lock" "$WORK/nix/packages/shellfirm/Cargo.lock"
  cp "$REPO_ROOT/nix/packages/agent-command-guard/Cargo.toml" \
    "$WORK/nix/packages/agent-command-guard/Cargo.toml"
  cp "$REPO_ROOT/nix/packages/agent-command-guard/Cargo.lock" \
    "$WORK/nix/packages/agent-command-guard/Cargo.lock"
  cp "$REPO_ROOT/flake.nix" "$WORK/flake.nix"
  cp "$REPO_ROOT/flake.lock" "$WORK/flake.lock"

  (
    cd "$WORK"
    git init -q
    git config user.email update-pins-test@example.invalid
    git config user.name "update-pins test"
    git config commit.gpgsign false
    git add flake.nix flake.lock nix/packages/shellfirm/Cargo.lock \
      nix/packages/agent-command-guard/Cargo.toml \
      nix/packages/agent-command-guard/Cargo.lock nix/pins/*.json
    git commit -q -m "initial managed files"
  )

  if [ -z "${UPDATE_PINS_TEST_BIN:-}" ] || [ ! -x "$UPDATE_PINS_TEST_BIN" ]; then
    echo "UPDATE_PINS_TEST_BIN must identify the Nix-built update-pins binary" >&2
    return 1
  fi
  case "$UPDATE_PINS_TEST_BIN" in
  /*) ;;
  *)
    echo "UPDATE_PINS_TEST_BIN must be an absolute path" >&2
    return 1
    ;;
  esac
  UPDATE_PINS_ZIP_BIN="$(command -v zip)"
  export UPDATE_PINS_TEST_BIN UPDATE_PINS_ZIP_BIN

  export UPDATE_PINS_FAKE_ROOT="$WORK"
  export UPDATE_PINS_COMMAND_LOG="$WORK/command.log"
  export UPDATE_PINS_FLAKE_UPDATE_LOG="$WORK/flake-update.log"
  export UPDATE_PINS_SHELLFIRM_BUILD_COUNT="$WORK/shellfirm-build-count"
  export UPDATE_PINS_SHELLFIRM_CHECK_COUNT="$WORK/shellfirm-check-count"
  export UPDATE_PINS_DIFIT_BUILD_COUNT="$WORK/difit-build-count"

  make_difit_tarball "$(flake_version yoshiko-pg/difit)"
  make_source_tarball

  STUB_DIR="$WORK/stub"
  mkdir -p "$STUB_DIR"

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
"api --include repos/vercel-labs/agent-browser/releases/latest")
  gh_response "${UPDATE_PINS_AGENT_BROWSER_TAG:-v$(flake_version vercel-labs/agent-browser)}"
  ;;
"api --include repos/kaplanelad/shellfirm/releases/latest")
  gh_response "${UPDATE_PINS_SHELLFIRM_TAG:-v$(jq -r .version "$UPDATE_PINS_FAKE_ROOT/nix/pins/shellfirm.json")}"
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
  printf -v command_line '%q ' curl "$@"
  printf '%s\n' "${command_line% }"
} >>"$UPDATE_PINS_COMMAND_LOG"

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
case "$url" in
https://registry.npmjs.org/difit/latest)
  printf '{"version":"%s"}\n' \
    "${UPDATE_PINS_DIFIT_VERSION:-$(sed -n 's|.*github:yoshiko-pg/difit/v\([^"]*\)";|\1|p' "$UPDATE_PINS_FAKE_ROOT/flake.nix")}" \
    >"$output_path"
  ;;
https://registry.npmjs.org/difit/-/difit-*.tgz)
  cp "$UPDATE_PINS_DIFIT_TARBALL" "$output_path"
  ;;
https://persistent.oaistatic.com/codex-app-prod/appcast.xml)
  version=${UPDATE_PINS_CODEX_APP_VERSION:-$(jq -r .version "$UPDATE_PINS_FAKE_ROOT/nix/pins/codex-app.json")}
  archive_url=${UPDATE_PINS_CODEX_APP_URL:-$(jq -r .url "$UPDATE_PINS_FAKE_ROOT/nix/pins/codex-app.json")}
  cat >"$output_path" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
  <channel>
    <item>
      <title>$version</title>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>
      <enclosure url="$archive_url" length="123" type="application/octet-stream" />
    </item>
  </channel>
</rss>
XML
  ;;
https://persistent.oaistatic.com/codex-app-prod/*.zip)
  app_name=$(jq -r .appName "$UPDATE_PINS_FAKE_ROOT/nix/pins/codex-app.json")
  bundle_identifier=$(jq -r .bundleIdentifier "$UPDATE_PINS_FAKE_ROOT/nix/pins/codex-app.json")
  display_name=$(jq -r .displayName "$UPDATE_PINS_FAKE_ROOT/nix/pins/codex-app.json")
  version=${UPDATE_PINS_CODEX_APP_BUNDLE_VERSION:-${UPDATE_PINS_CODEX_APP_VERSION:-$(jq -r .version "$UPDATE_PINS_FAKE_ROOT/nix/pins/codex-app.json")}}
  fixture="$UPDATE_PINS_FAKE_ROOT/codex-app-fixture"
  rm -rf "$fixture"
  mkdir -p "$fixture/$app_name/Contents"
  cat >"$fixture/$app_name/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key><string>$display_name</string>
  <key>CFBundleIdentifier</key><string>$bundle_identifier</string>
  <key>CFBundleName</key><string>$display_name</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
</dict>
</plist>
PLIST
  rm -f "$output_path"
  (
    cd "$fixture"
    "$UPDATE_PINS_ZIP_BIN" -q -r "$output_path" "$app_name"
  )
  rm -rf "$fixture"
  ;;
https://github.com/kaplanelad/shellfirm/archive/refs/tags/*.tar.gz)
  cp "$UPDATE_PINS_SOURCE_TARBALL" "$output_path"
  printf '%s\n' "$output_path" >"$UPDATE_PINS_FAKE_ROOT/shellfirm-download-path"
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
printf 'npm %s\n' "$*" >>"$UPDATE_PINS_COMMAND_LOG"
echo "npm must not be invoked by update-pins" >&2
exit 97
EOS

  printf '#!%s\n' "$BASH_BIN" >"$STUB_DIR/cargo"
  cat >>"$STUB_DIR/cargo" <<'EOS'
set -euo pipefail
printf 'cargo %s\n' "$*" >>"$UPDATE_PINS_COMMAND_LOG"
if [ "$#" -ne 7 ] \
  || [ "$1" != "update" ] \
  || [ "$2" != "--manifest-path" ] \
  || [ "$4" != "--package" ] \
  || [ "$5" != "shellfirm" ] \
  || [ "$6" != "--precise" ]; then
  echo "unexpected cargo invocation: $*" >&2
  exit 1
fi
manifest=$3
version=$7
cat >"$(dirname "$manifest")/Cargo.lock" <<LOCK
version = 4

[[package]]
name = "agent-command-guard"
version = "0.1.0"
dependencies = [
 "shellfirm",
]

[[package]]
name = "shellfirm"
version = "$version"
source = "registry+https://github.com/rust-lang/crates.io-index"
checksum = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
LOCK
EOS

  printf '#!%s\n' "$BASH_BIN" >"$STUB_DIR/nix"
  cat >>"$STUB_DIR/nix" <<'EOS'
set -euo pipefail

{
  printf -v command_line '%q ' nix "$@"
  printf '%s\n' "${command_line% }"
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
  local_path=${local_url#file://}
  [ "$local_path" != "$local_url" ] && [ -f "$local_path" ]

  if [ -f "$UPDATE_PINS_FAKE_ROOT/shellfirm-download-path" ] \
    && [ "$(cat "$UPDATE_PINS_FAKE_ROOT/shellfirm-download-path")" = "$local_path" ]; then
    store="$UPDATE_PINS_FAKE_ROOT/shellfirm-store"
    version=${UPDATE_PINS_SHELLFIRM_TAG:-v$(jq -r .version "$UPDATE_PINS_FAKE_ROOT/nix/pins/shellfirm.json")}
    version=${version#v}
    mkdir -p "$store/shellfirm"
    printf '[workspace]\nmembers = ["shellfirm"]\n' >"$store/Cargo.toml"
    printf '[package]\nname = "shellfirm"\nversion = "%s"\n' "$version" >"$store/shellfirm/Cargo.toml"
    cat >"$store/Cargo.lock" <<LOCK
version = 4

[[package]]
name = "fixture-dependency"
version = "1.0.0"
source = "registry+https://github.com/rust-lang/crates.io-index"
checksum = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

[[package]]
name = "shellfirm"
version = "$version"
LOCK
    printf '{"hash":"sha256-JaZjQmPBsfb8RpegTiuZBOpLBCqJr1nck+wfXUSEiiY=","storePath":"%s"}\n' "$store"
    exit 0
  fi

  case "$local_path" in
  *.zip)
    zip_path="$UPDATE_PINS_FAKE_ROOT/codex-app.zip"
    cp "$local_path" "$zip_path"
    printf '{"hash":"sha256-V95M9AFEvffQABDy9VV6fWQsK5cFMJv63hZ90xPiypM=","storePath":"%s"}\n' "$zip_path"
    ;;
  *.json)
    printf '{"hash":"%s"}\n' "${UPDATE_PINS_SCHEMA_HASH:-sha256-3wrW5DiA8JyQ6/lfGREBeKumiQ3wAQ69p0hQKeK1Q7Q=}"
    ;;
  *.tgz)
    printf '{"hash":"sha256-gmer9Ei3Jq/YwFQ13VuGqxjSZiafe7wWoJnabLgSrKE=","storePath":"%s"}\n' "$UPDATE_PINS_DIFIT_TARBALL"
    ;;
  *)
    if [ "$#" -eq 7 ]; then
      printf '{"hash":"sha256-JaZjQmPBsfb8RpegTiuZBOpLBCqJr1nck+wfXUSEiiY="}\n'
    else
      printf '{"hash":"sha256-1ZOG4K5DXikvvg6825VLde1fs5IgkSd8sZ95j8XVBxg="}\n'
    fi
    ;;
  esac
  exit 0
fi

if [ "$1" = "build" ] \
  && [ "${2:-}" = "--impure" ] \
  && [ "${3:-}" = "--expr" ] \
  && [ "${5:-}" = "--no-link" ] \
  && [ "${UPDATE_PINS_PACKAGE:-}" = "difit" ]; then
  count=0
  if [ -f "$UPDATE_PINS_DIFIT_BUILD_COUNT" ]; then
    count=$(cat "$UPDATE_PINS_DIFIT_BUILD_COUNT")
  fi
  count=$((count + 1))
  printf '%s\n' "$count" >"$UPDATE_PINS_DIFIT_BUILD_COUNT"
  if [ "$count" -eq 1 ]; then
    [ "${UPDATE_PINS_PIN_OVERRIDE:-}" = "difitPin" ]
    [ "${UPDATE_PINS_DEPENDENCY_HASH_FIELD:-}" = "pnpmDepsHash" ]
    printf 'candidate-build-env %s %s %s\n' \
      "$UPDATE_PINS_PACKAGE" \
      "$UPDATE_PINS_PIN_OVERRIDE" \
      "$UPDATE_PINS_DEPENDENCY_HASH_FIELD" >>"$UPDATE_PINS_COMMAND_LOG"
    echo "error: hash mismatch" >&2
    echo "got: sha256-32X0K6wkLW2x9cJJJ6J+cu5HOM2+oTZe5AEqLRHvpPM=" >&2
    exit 1
  fi
  exit 0
fi

if [ "$1" = "build" ] \
  && [ "${2:-}" = "--impure" ] \
  && [ "${3:-}" = "--expr" ] \
  && [ "${5:-}" = "--no-link" ] \
  && [ "${6:-}" = "--print-out-paths" ] \
  && [ "${UPDATE_PINS_CHECK:-}" = "agent-command-shellfirm-catalog" ]; then
  count=0
  if [ -f "$UPDATE_PINS_SHELLFIRM_CHECK_COUNT" ]; then
    count=$(cat "$UPDATE_PINS_SHELLFIRM_CHECK_COUNT")
  fi
  count=$((count + 1))
  printf '%s\n' "$count" >"$UPDATE_PINS_SHELLFIRM_CHECK_COUNT"
  if [ "${UPDATE_PINS_FAIL_CANDIDATE_POLICY:-0}" = 1 ] && [ "$count" -eq 2 ]; then
    echo "candidate command policy rejected" >&2
    exit 1
  fi
  output="$UPDATE_PINS_FAKE_ROOT/shellfirm-catalog-$count"
  mkdir -p "$output"
  if [ "$count" -eq 1 ]; then
    printf 'git:force_push\nshell:rm_rf\n' >"$output/effective-shellfirm-rules.txt"
  else
    printf 'fs:overwrite_device\ngit:force_push\n' >"$output/effective-shellfirm-rules.txt"
  fi
  printf '%s\n' "$output"
  exit 0
fi

if [ "$1" = "build" ] \
  && [ "${2:-}" = "--impure" ] \
  && [ "${3:-}" = "--expr" ] \
  && [ "${5:-}" = "--no-link" ] \
  && [ "${UPDATE_PINS_PACKAGE:-}" = "shellfirm" ]; then
  count=0
  if [ -f "$UPDATE_PINS_SHELLFIRM_BUILD_COUNT" ]; then
    count=$(cat "$UPDATE_PINS_SHELLFIRM_BUILD_COUNT")
  fi
  printf '%s\n' "$((count + 1))" >"$UPDATE_PINS_SHELLFIRM_BUILD_COUNT"
  exit 0
fi

if [ "$1" = "flake" ] && [ "${2:-}" = "update" ]; then
  input=${3:-}
  printf '%s\n' "$input" >>"$UPDATE_PINS_FLAKE_UPDATE_LOG"
  case "$input" in
  hcom-src) repo=aannoo/hcom ;;
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
  exit 0
fi

echo "unexpected nix invocation: $*" >&2
exit 1
EOS

  chmod +x "$STUB_DIR/gh" "$STUB_DIR/curl" "$STUB_DIR/npm" \
    "$STUB_DIR/cargo" "$STUB_DIR/nix"
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
  mkdir -p "$dst/nix/pins" "$dst/nix/packages/shellfirm" \
    "$dst/nix/packages/agent-command-guard"
  cp -p "$WORK/flake.nix" "$dst/flake.nix"
  cp -p "$WORK/flake.lock" "$dst/flake.lock"
  cp -p "$WORK"/nix/pins/*.json "$dst/nix/pins/"
  cp -p "$WORK/nix/packages/shellfirm/Cargo.lock" "$dst/nix/packages/shellfirm/Cargo.lock"
  cp -p "$WORK/nix/packages/agent-command-guard/Cargo.toml" \
    "$dst/nix/packages/agent-command-guard/Cargo.toml"
  cp -p "$WORK/nix/packages/agent-command-guard/Cargo.lock" \
    "$dst/nix/packages/agent-command-guard/Cargo.lock"
}

file_mode() {
  if stat -c '%a' "$1" >/dev/null 2>&1; then
    stat -c '%a' "$1"
  else
    stat -f '%Lp' "$1"
  fi
}

assert_managed_matches() {
  local expected=$1 pin name
  cmp -s "$WORK/flake.nix" "$expected/flake.nix"
  [ "$(file_mode "$WORK/flake.nix")" = "$(file_mode "$expected/flake.nix")" ]
  cmp -s "$WORK/flake.lock" "$expected/flake.lock"
  [ "$(file_mode "$WORK/flake.lock")" = "$(file_mode "$expected/flake.lock")" ]
  cmp -s "$WORK/nix/packages/shellfirm/Cargo.lock" "$expected/nix/packages/shellfirm/Cargo.lock"
  [ "$(file_mode "$WORK/nix/packages/shellfirm/Cargo.lock")" = "$(file_mode "$expected/nix/packages/shellfirm/Cargo.lock")" ]
  cmp -s "$WORK/nix/packages/agent-command-guard/Cargo.toml" \
    "$expected/nix/packages/agent-command-guard/Cargo.toml"
  cmp -s "$WORK/nix/packages/agent-command-guard/Cargo.lock" \
    "$expected/nix/packages/agent-command-guard/Cargo.lock"
  for pin in "$expected"/nix/pins/*.json; do
    name=$(basename "$pin")
    cmp -s "$WORK/nix/pins/$name" "$pin"
    [ "$(file_mode "$WORK/nix/pins/$name")" = "$(file_mode "$pin")" ]
  done
}

assert_no_staging_files() {
  local leftover
  leftover=$(find "$WORK" -name '*.update-pins*' -print -quit)
  [ -z "$leftover" ]
}

flake_version() {
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

assert_check_lock_reacquirable() {
  run_update_pins --check codex-app
  [ "$status" -eq 0 ]
}

@test "Nix-built public binary preserves help, parse, and exit contracts" {
  original="$WORK/original"
  save_managed "$original"

  run_update_pins --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: update-pins [--check] [--force] [--jobs N] [--retry N] [target]"* ]]
  [[ "$output" == *"codex-app"* ]]

  run_update_pins unknown
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown target 'unknown'"* ]]

  run_update_pins hcom codex-app
  [ "$status" -eq 2 ]
  [[ "$output" == *"expected at most one target"* ]]

  run_update_pins --retry 0
  [ "$status" -eq 2 ]
  [[ "$output" == *"--retry must be an integer from 1 to 5"* ]]

  run_update_pins --jobs 5
  [ "$status" -eq 2 ]
  [[ "$output" == *"--jobs must be an integer from 1 to 4"* ]]

  [ ! -e "$UPDATE_PINS_COMMAND_LOG" ]
  assert_managed_matches "$original"
}

@test "check reports a candidate and restores bytes, modes, and lock" {
  chmod 0440 "$WORK/nix/pins/hcom.json"
  chmod 0640 "$WORK/flake.nix"
  chmod 0600 "$WORK/flake.lock"
  original="$WORK/original"
  save_managed "$original"
  export UPDATE_PINS_HCOM_TAG=v9.9.9

  run_update_pins --check hcom

  [ "$status" -eq 0 ]
  section=$(report_section "Candidate changes:")
  [ "$(printf '%s\n' "$section" | sed -n 's/^  \([^ ].*\):$/\1/p')" = "hcom" ]
  [[ "$section" == *"version:"* ]]
  [[ "$section" == *"flake input [hcom-src]: changed"* ]]
  [[ "$output" == *"hcom check succeeded; no managed changes were kept."* ]]
  assert_managed_matches "$original"
  assert_no_staging_files
  assert_check_lock_reacquirable
}

@test "Difit update preserves real child argv, hash refresh order, and provenance" {
  original="$WORK/original"
  save_managed "$original"
  export UPDATE_PINS_DIFIT_VERSION=9.9.9
  make_difit_tarball "$UPDATE_PINS_DIFIT_VERSION"

  run_update_pins difit

  [ "$status" -eq 0 ]
  [ "$(jq -r .srcHash "$WORK/nix/pins/difit.json")" = "sha256-gmer9Ei3Jq/YwFQ13VuGqxjSZiafe7wWoJnabLgSrKE=" ]
  [ "$(jq -r .pnpmDepsHash "$WORK/nix/pins/difit.json")" = "sha256-32X0K6wkLW2x9cJJJ6J+cu5HOM2+oTZe5AEqLRHvpPM=" ]
  jq -e 'keys == ["pnpmDepsHash", "srcHash"]' "$WORK/nix/pins/difit.json"
  grep -Fq 'url = "github:yoshiko-pg/difit/v9.9.9";' "$WORK/flake.nix"
  [ "$(flake_lock_ref difit-src)" = "v9.9.9" ]
  [ "$(cat "$UPDATE_PINS_DIFIT_BUILD_COUNT")" -eq 2 ]
  flake_update_line=$(grep -n '^nix flake update difit-src$' "$UPDATE_PINS_COMMAND_LOG" | cut -d: -f1)
  candidate_build_line=$(grep -n '^candidate-build-env difit difitPin pnpmDepsHash$' "$UPDATE_PINS_COMMAND_LOG" | cut -d: -f1)
  [ "$flake_update_line" -lt "$candidate_build_line" ]
  ! grep -q '^npm ' "$UPDATE_PINS_COMMAND_LOG"
  [ ! -e "$WORK/nix/packages/difit/package-lock.json" ]

  cp "$WORK/nix/pins/difit.json" "$original/nix/pins/difit.json"
  cp "$WORK/flake.nix" "$original/flake.nix"
  cp "$WORK/flake.lock" "$original/flake.lock"
  assert_managed_matches "$original"
}

@test "Shellfirm candidate policy failure restores all four synchronized files" {
  original="$WORK/original"
  save_managed "$original"
  export UPDATE_PINS_SHELLFIRM_TAG=v8.8.8
  export UPDATE_PINS_FAIL_CANDIDATE_POLICY=1

  run_update_pins shellfirm

  [ "$status" -eq 1 ]
  [[ "$output" == *"candidate command policy rejected"* ]]
  [[ "$output" == *"restoring managed files from backup"* ]]
  [ "$(cat "$UPDATE_PINS_SHELLFIRM_CHECK_COUNT")" -eq 2 ]
  assert_managed_matches "$original"
  assert_no_staging_files
}

@test "Shellfirm update synchronizes guard pins and reports effective rule changes" {
  export UPDATE_PINS_SHELLFIRM_TAG=v8.8.8

  run_update_pins shellfirm

  [ "$status" -eq 0 ]
  [ "$(jq -r .version "$WORK/nix/pins/shellfirm.json")" = 8.8.8 ]
  grep -Fq 'shellfirm = { version = "=8.8.8", default-features = false }' \
    "$WORK/nix/packages/agent-command-guard/Cargo.toml"
  grep -A2 -F 'name = "shellfirm"' \
    "$WORK/nix/packages/agent-command-guard/Cargo.lock" \
    | grep -Fq 'version = "8.8.8"'
  grep -A1 -F 'name = "shellfirm"' \
    "$WORK/nix/packages/shellfirm/Cargo.lock" \
    | grep -Fq 'version = "8.8.8"'
  [[ "$output" == *$'  added:\n    fs:overwrite_device'* ]]
  [[ "$output" == *$'  removed:\n    shell:rm_rf'* ]]
  [ "$(cat "$UPDATE_PINS_SHELLFIRM_CHECK_COUNT")" -eq 2 ]
  [ "$(cat "$UPDATE_PINS_SHELLFIRM_BUILD_COUNT")" -eq 1 ]
}

@test "paired Agent Browser update publishes every asset with its flake input" {
  original="$WORK/original"
  save_managed "$original"
  export UPDATE_PINS_AGENT_BROWSER_TAG=v9.9.9

  run_update_pins agent-browser

  [ "$status" -eq 0 ]
  jq -e 'all(.assets[]; .hash == "sha256-1ZOG4K5DXikvvg6825VLde1fs5IgkSd8sZ95j8XVBxg=")' \
    "$WORK/nix/pins/agent-browser.json"
  grep -Fq 'url = "github:vercel-labs/agent-browser/v9.9.9";' "$WORK/flake.nix"
  [ "$(flake_lock_ref agent-browser-skill)" = "v9.9.9" ]
  [ "$(cat "$UPDATE_PINS_FLAKE_UPDATE_LOG")" = "agent-browser-skill" ]

  cp "$WORK/nix/pins/agent-browser.json" "$original/nix/pins/agent-browser.json"
  cp "$WORK/flake.nix" "$original/flake.nix"
  cp "$WORK/flake.lock" "$original/flake.lock"
  assert_managed_matches "$original"
}

@test "Codex app update validates a real ZIP and plist identity" {
  original="$WORK/original"
  save_managed "$original"
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
