#!/usr/bin/env bats

DOTFILES_TEST_REPO_ROOT=${DOTFILES_TEST_REPO_ROOT:-$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)}

setup() {
  BASH_BIN=$(command -v bash)
  REPO_ROOT="$BATS_TEST_TMPDIR/repository"
  MOCK_BIN="$BATS_TEST_TMPDIR/bin"
  UPDATE_SCRIPT="$DOTFILES_TEST_REPO_ROOT/modules/features/ci/_scripts/update-gha-diag.sh"
  FEATURE_EXTRACTOR="$DOTFILES_TEST_REPO_ROOT/modules/features/ci/_scripts/extract-gha-diag-experimental-features.mjs"
  LICENSE_GENERATOR="$DOTFILES_TEST_REPO_ROOT/modules/features/ci/_scripts/generate-gha-diag-node-licenses.mjs"
  mkdir -p "$REPO_ROOT" "$MOCK_BIN"

  cat >"$MOCK_BIN/git" <<EOF
#!$BASH_BIN
printf '%s\n' '$REPO_ROOT'
EOF
  chmod +x "$MOCK_BIN/git"
}

make_license_fixture() {
  LICENSE_SOURCE="$BATS_TEST_TMPDIR/source"
  LICENSE_BUNDLE="$BATS_TEST_TMPDIR/bundle.cjs"
  LICENSE_REBUILT_BUNDLE="$BATS_TEST_TMPDIR/rebuilt-bundle.cjs"
  LICENSE_METAFILE="$BATS_TEST_TMPDIR/metafile.json"
  LICENSE_REVISION=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  local dependency="$LICENSE_SOURCE/node_modules/example"
  local nested="$LICENSE_SOURCE/languageserver/node_modules/outer/node_modules/nested"
  mkdir -p \
    "$LICENSE_SOURCE/.git" \
    "$LICENSE_SOURCE/expressions/dist" \
    "$LICENSE_SOURCE/languageserver/src" \
    "$LICENSE_SOURCE/languageservice/dist" \
    "$LICENSE_SOURCE/workflow-parser/dist" \
    "$dependency" \
    "$nested"
  printf '%s\n' "$LICENSE_REVISION" >"$LICENSE_SOURCE/.git/HEAD"
  printf '%s\n' 'MIT License' >"$LICENSE_SOURCE/LICENSE"

  cat >"$LICENSE_SOURCE/expressions/package.json" <<'JSON'
{ "name": "@actions/expressions", "version": "1.2.3", "license": "MIT", "engines": { "node": ">= 20" } }
JSON
  cat >"$LICENSE_SOURCE/languageserver/package.json" <<'JSON'
{ "name": "@actions/languageserver", "version": "1.2.3", "license": "MIT", "engines": { "node": ">= 20" } }
JSON
  cat >"$LICENSE_SOURCE/languageservice/package.json" <<'JSON'
{ "name": "@actions/languageservice", "version": "1.2.3", "license": "MIT", "engines": { "node": ">= 20" } }
JSON
  cat >"$LICENSE_SOURCE/workflow-parser/package.json" <<'JSON'
{ "name": "@actions/workflow-parser", "version": "1.2.3", "license": "MIT", "engines": { "node": ">= 20" } }
JSON

  cat >"$LICENSE_SOURCE/package-lock.json" <<'JSON'
{
  "packages": {
    "expressions": {
      "name": "@actions/expressions", "version": "1.2.3", "license": "MIT", "engines": { "node": ">= 20" }
    },
    "languageserver": {
      "name": "@actions/languageserver", "version": "1.2.3", "license": "MIT", "engines": { "node": ">= 20" }
    },
    "languageservice": {
      "name": "@actions/languageservice", "version": "1.2.3", "license": "MIT", "engines": { "node": ">= 20" }
    },
    "workflow-parser": {
      "name": "@actions/workflow-parser", "version": "1.2.3", "license": "MIT", "engines": { "node": ">= 20" }
    },
    "node_modules/@actions/expressions": { "resolved": "expressions", "link": true },
    "node_modules/@actions/languageservice": { "resolved": "languageservice", "link": true },
    "node_modules/@actions/workflow-parser": { "resolved": "workflow-parser", "link": true },
    "node_modules/esbuild": {
      "version": "0.27.1",
      "resolved": "https://registry.npmjs.org/esbuild/-/esbuild-0.27.1.tgz",
      "integrity": "sha512-esbuild"
    },
    "node_modules/example": {
      "version": "1.2.3",
      "resolved": "https://registry.npmjs.org/example/-/example-1.2.3.tgz",
      "integrity": "sha512-example"
    },
    "languageserver/node_modules/outer/node_modules/nested": {
      "version": "4.5.6",
      "resolved": "https://registry.npmjs.org/nested/-/nested-4.5.6.tgz",
      "integrity": "sha512-nested"
    }
  }
}
JSON
  cat >"$dependency/package.json" <<'JSON'
{ "name": "example", "version": "1.2.3", "license": "MIT" }
JSON
  cat >"$dependency/LICENSE" <<'TEXT'
MIT License
Copyright Example Authors
TEXT
  cat >"$dependency/thirdpartynotices.txt" <<'TEXT'
NOTICES AND INFORMATION
Example embedded notice
TEXT
  cat >"$nested/package.json" <<'JSON'
{ "name": "nested", "version": "4.5.6", "license": "ISC" }
JSON
  cat >"$nested/LICENSE" <<'TEXT'
ISC License
Copyright Nested Authors
TEXT
  printf '%s\n' 'module.exports = {};' >"$dependency/index.js"
  printf '%s\n' 'module.exports = {};' >"$nested/index.js"
  printf '%s\n' 'export {};' >"$LICENSE_SOURCE/languageserver/src/index.ts"
  cat >"$LICENSE_BUNDLE" <<'JS'
// ../node_modules/example/index.js
// node_modules/outer/node_modules/nested/index.js
module.exports = {};
JS
  cp "$LICENSE_BUNDLE" "$LICENSE_REBUILT_BUNDLE"
  cat >"$LICENSE_METAFILE" <<'JSON'
{
  "outputs": {
    "dist/cli.bundle.cjs": {
      "imports": [{ "path": "node:fs", "kind": "require-call", "external": true }],
      "entryPoint": "src/index.ts",
      "inputs": {
        "src/index.ts": { "bytesInOutput": 1 },
        "../node_modules/example/index.js": { "bytesInOutput": 10 },
        "node_modules/outer/node_modules/nested/index.js": { "bytesInOutput": 20 }
      },
      "bytes": 100
    }
  }
}
JSON
}

@test "license generator records exact metafile packages and notices" {
  make_license_fixture

  run node "$LICENSE_GENERATOR" \
    "$LICENSE_SOURCE" \
    "$LICENSE_BUNDLE" \
    "$LICENSE_REBUILT_BUNDLE" \
    "$LICENSE_METAFILE" \
    "$BATS_TEST_TMPDIR/LICENSE-THIRD-PARTY" \
    "$BATS_TEST_TMPDIR/inventory.json"

  [ "$status" -eq 0 ]
  grep -Fq 'Package: example@1.2.3' "$BATS_TEST_TMPDIR/LICENSE-THIRD-PARTY"
  grep -Fq 'Package: nested@4.5.6' "$BATS_TEST_TMPDIR/LICENSE-THIRD-PARTY"
  grep -Fq 'NOTICES AND INFORMATION' "$BATS_TEST_TMPDIR/LICENSE-THIRD-PARTY"
  [ "$(jq -r '.packages | length' "$BATS_TEST_TMPDIR/inventory.json")" -eq 2 ]
  [ "$(jq -r '.upstreamRevision' "$BATS_TEST_TMPDIR/inventory.json")" = "$LICENSE_REVISION" ]
  [ "$(jq -r '.schemaVersion' "$BATS_TEST_TMPDIR/inventory.json")" = 'gha-diag-node-licenses-v2' ]
  [ "$(jq -r '.reproduction.byteForByte' "$BATS_TEST_TMPDIR/inventory.json")" = true ]
  [ "$(jq -r '.packages[] | select(.name == "example") | .bytesInOutput' "$BATS_TEST_TMPDIR/inventory.json")" -eq 10 ]
}

@test "license generator rejects a license outside the reviewed set" {
  make_license_fixture
  jq '.license = "GPL-3.0-only"' \
    "$LICENSE_SOURCE/node_modules/example/package.json" \
    >"$BATS_TEST_TMPDIR/package.json"
  mv "$BATS_TEST_TMPDIR/package.json" \
    "$LICENSE_SOURCE/node_modules/example/package.json"

  run node "$LICENSE_GENERATOR" \
    "$LICENSE_SOURCE" \
    "$LICENSE_BUNDLE" \
    "$LICENSE_REBUILT_BUNDLE" \
    "$LICENSE_METAFILE" \
    "$BATS_TEST_TMPDIR/LICENSE-THIRD-PARTY" \
    "$BATS_TEST_TMPDIR/inventory.json"

  [ "$status" -ne 0 ]
  [[ "$output" == *"unreviewed license"* ]]
}

@test "license generator rejects missing license notices" {
  make_license_fixture
  rm "$LICENSE_SOURCE/node_modules/example/LICENSE"
  rm "$LICENSE_SOURCE/node_modules/example/thirdpartynotices.txt"

  run node "$LICENSE_GENERATOR" \
    "$LICENSE_SOURCE" \
    "$LICENSE_BUNDLE" \
    "$LICENSE_REBUILT_BUNDLE" \
    "$LICENSE_METAFILE" \
    "$BATS_TEST_TMPDIR/LICENSE-THIRD-PARTY" \
    "$BATS_TEST_TMPDIR/inventory.json"

  [ "$status" -ne 0 ]
  [[ "$output" == *"has no LICENSE, COPYING, or NOTICE"* ]]
}

@test "license generator rejects a bundle reproduction mismatch" {
  make_license_fixture
  printf '%s\n' '// changed' >>"$LICENSE_REBUILT_BUNDLE"

  run node "$LICENSE_GENERATOR" \
    "$LICENSE_SOURCE" \
    "$LICENSE_BUNDLE" \
    "$LICENSE_REBUILT_BUNDLE" \
    "$LICENSE_METAFILE" \
    "$BATS_TEST_TMPDIR/LICENSE-THIRD-PARTY" \
    "$BATS_TEST_TMPDIR/inventory.json"

  [ "$status" -ne 0 ]
  [[ "$output" == *"does not byte-for-byte match"* ]]
}

make_update_fixture() {
  TEST_VERSION=1.2.4
  TEST_GIT_HEAD=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  SOURCE_FIXTURE="$BATS_TEST_TMPDIR/update-source"
  TOOL_FIXTURE="$BATS_TEST_TMPDIR/update-tool"
  METADATA_FIXTURE="$BATS_TEST_TMPDIR/update-metadata"
  FIXTURE_BUNDLE="$BATS_TEST_TMPDIR/published-cli.bundle.cjs"
  FIXTURE_METAFILE="$BATS_TEST_TMPDIR/update-metafile.json"
  ARCHIVE="$BATS_TEST_TMPDIR/languageserver.tgz"
  local archive_root="$BATS_TEST_TMPDIR/archive"
  local platform
  local platform_os
  local platform_cpu
  platform=$(node -p 'process.platform + "-" + process.arch')
  platform_os=${platform%-*}
  platform_cpu=${platform#*-}
  [[ "$platform" == @(darwin-arm64|darwin-x64|linux-arm64|linux-x64) ]]

  mkdir -p \
    "$SOURCE_FIXTURE/.git" \
    "$SOURCE_FIXTURE/expressions" \
    "$SOURCE_FIXTURE/languageserver/src" \
    "$SOURCE_FIXTURE/languageservice" \
    "$SOURCE_FIXTURE/node_modules/example" \
    "$SOURCE_FIXTURE/workflow-parser" \
    "$TOOL_FIXTURE/node_modules/@actions/languageserver/dist" \
    "$TOOL_FIXTURE/node_modules/esbuild/bin" \
    "$METADATA_FIXTURE" \
    "$archive_root/package/dist" \
    "$REPO_ROOT/modules/features/ci/_scripts" \
    "$REPO_ROOT/modules/features/ci/_packages/gha-diag/vendor"
  cp "$FEATURE_EXTRACTOR" \
    "$REPO_ROOT/modules/features/ci/_scripts/extract-gha-diag-experimental-features.mjs"
  cp "$LICENSE_GENERATOR" \
    "$REPO_ROOT/modules/features/ci/_scripts/generate-gha-diag-node-licenses.mjs"
  printf '%s\n' "$TEST_GIT_HEAD" >"$SOURCE_FIXTURE/.git/HEAD"
  printf '%s\n' 'MIT License' >"$SOURCE_FIXTURE/LICENSE"
  printf '%s\n' 'export {};' >"$SOURCE_FIXTURE/languageserver/src/index.ts"
  printf '%s\n' 'module.exports = {};' >"$SOURCE_FIXTURE/node_modules/example/index.js"
  printf '%s\n' 'MIT License for example' >"$SOURCE_FIXTURE/node_modules/example/LICENSE"
  jq -n \
    --arg version "$TEST_VERSION" \
    '{name: "example", version: $version, license: "MIT"}' \
    >"$SOURCE_FIXTURE/node_modules/example/package.json"

  for unscoped in expressions languageserver languageservice workflow-parser; do
    jq -n \
      --arg name "@actions/$unscoped" \
      --arg version "$TEST_VERSION" \
      '{name: $name, version: $version, license: "MIT", engines: {node: ">= 20"}}' \
      >"$SOURCE_FIXTURE/$unscoped/package.json"
  done

  jq -n \
    --arg version "$TEST_VERSION" \
    --arg platform_path "node_modules/@esbuild/$platform" \
    --arg platform_os "$platform_os" \
    --arg platform_cpu "$platform_cpu" \
    '{
      packages: {
        expressions: {name: "@actions/expressions", version: $version, license: "MIT", engines: {node: ">= 20"}},
        languageserver: {name: "@actions/languageserver", version: $version, license: "MIT", engines: {node: ">= 20"}},
        languageservice: {name: "@actions/languageservice", version: $version, license: "MIT", engines: {node: ">= 20"}},
        "workflow-parser": {name: "@actions/workflow-parser", version: $version, license: "MIT", engines: {node: ">= 20"}},
        "node_modules/@actions/expressions": {resolved: "expressions", link: true},
        "node_modules/@actions/languageservice": {resolved: "languageservice", link: true},
        "node_modules/@actions/workflow-parser": {resolved: "workflow-parser", link: true},
        "node_modules/esbuild": {
          version: "0.27.1",
          resolved: "https://registry.npmjs.org/esbuild/-/esbuild-0.27.1.tgz",
          integrity: "sha512-esbuild"
        },
        ($platform_path): {
          version: "0.27.1",
          integrity: "sha512-platform",
          optional: true,
          os: [$platform_os],
          cpu: [$platform_cpu]
        },
        "node_modules/example": {
          version: $version,
          resolved: ("https://registry.npmjs.org/example/-/example-" + $version + ".tgz"),
          integrity: "sha512-example"
        }
      }
    }' >"$SOURCE_FIXTURE/package-lock.json"

  cat >"$FIXTURE_BUNDLE" <<'JS'
// ../node_modules/example/index.js
// actions/readFile
module.exports = {};
JS
  cp "$FIXTURE_BUNDLE" "$archive_root/package/dist/cli.bundle.cjs"
  printf '%s\n' 'MIT License for actions/languageservices' >"$archive_root/package/LICENSE"
  tar -czf "$ARCHIVE" -C "$archive_root" package
  printf '#!%s\n' "$BASH_BIN" >"$MOCK_BIN/openssl"
  cat >>"$MOCK_BIN/openssl" <<'SH'
printf '%s' 'fixture-sha512-digest'
SH
  chmod +x "$MOCK_BIN/openssl"
  TEST_INTEGRITY="sha512-$("$MOCK_BIN/openssl" dgst -sha512 -binary "$ARCHIVE" | base64 --wrap=0)"

  cat >"$FIXTURE_METAFILE" <<'JSON'
{
  "outputs": {
    "dist/cli.bundle.cjs": {
      "imports": [],
      "entryPoint": "src/index.ts",
      "inputs": {
        "src/index.ts": { "bytesInOutput": 1 },
        "../node_modules/example/index.js": { "bytesInOutput": 10 }
      },
      "bytes": 100
    }
  }
}
JSON

  jq -n \
    --arg version "$TEST_VERSION" \
    --arg git_head "$TEST_GIT_HEAD" \
    --arg integrity "$TEST_INTEGRITY" \
    '{
      name: "@actions/languageserver",
      version: $version,
      license: "MIT",
      engines: {node: ">= 20"},
      repository: {url: "git+https://github.com/actions/languageservices.git"},
      gitHead: $git_head,
      time: {($version): "2026-08-04T19:25:30.652Z"},
      dist: {
        integrity: $integrity,
        tarball: ("https://registry.npmjs.org/@actions/languageserver/-/languageserver-" + $version + ".tgz"),
        attestations: {url: "https://registry.npmjs.org/attestation", provenance: {predicateType: "https://slsa.dev/provenance/v1"}},
        signatures: [{keyid: "SHA256:key"}]
      }
    }' >"$METADATA_FIXTURE/languageserver.json"

  for unscoped in expressions languageservice workflow-parser; do
    mkdir -p "$TOOL_FIXTURE/node_modules/@actions/$unscoped/dist"
    printf '%s\n' 'MIT License for actions/languageservices' \
      >"$TOOL_FIXTURE/node_modules/@actions/$unscoped/LICENSE"
    printf '%s\n' 'export {};' \
      >"$TOOL_FIXTURE/node_modules/@actions/$unscoped/dist/index.js"
    jq -n \
      --arg name "@actions/$unscoped" \
      --arg version "$TEST_VERSION" \
      '{
        name: $name,
        version: $version,
        license: "MIT",
        engines: {node: ">= 20"},
        repository: {url: "https://github.com/actions/languageservices"}
      }' >"$TOOL_FIXTURE/node_modules/@actions/$unscoped/package.json"
    jq -n \
      --arg name "@actions/$unscoped" \
      --arg version "$TEST_VERSION" \
      --arg git_head "$TEST_GIT_HEAD" \
      --arg integrity "sha512-$unscoped" \
      --arg tarball "https://registry.npmjs.org/@actions/$unscoped/-/$unscoped-$TEST_VERSION.tgz" \
      '{
        name: $name,
        version: $version,
        license: "MIT",
        engines: {node: ">= 20"},
        repository: {url: "git+https://github.com/actions/languageservices.git"},
        gitHead: $git_head,
        dist: {
          integrity: $integrity,
          tarball: $tarball,
          attestations: {provenance: {predicateType: "https://slsa.dev/provenance/v1"}},
          signatures: [{keyid: "SHA256:key"}]
        }
      }' >"$METADATA_FIXTURE/$unscoped.json"
  done
  cat >"$TOOL_FIXTURE/node_modules/@actions/expressions/dist/index.js" <<'JS'
export class FeatureFlags {
  constructor(features = {}) {
    this.features = features;
  }

  getEnabledFeatures() {
    if (!this.features.all) return [];
    return ["fixtureFeature", "otherFixtureFeature"].filter(
      (feature) => this.features[feature] !== false,
    );
  }
}
JS
  jq '.type = "module"' \
    "$TOOL_FIXTURE/node_modules/@actions/expressions/package.json" \
    >"$BATS_TEST_TMPDIR/expressions-package.json"
  mv "$BATS_TEST_TMPDIR/expressions-package.json" \
    "$TOOL_FIXTURE/node_modules/@actions/expressions/package.json"

  cp "$FIXTURE_BUNDLE" \
    "$TOOL_FIXTURE/node_modules/@actions/languageserver/dist/cli.bundle.cjs"
  cp "$archive_root/package/LICENSE" \
    "$TOOL_FIXTURE/node_modules/@actions/languageserver/LICENSE"
  jq -n \
    --arg version "$TEST_VERSION" \
    '{
      name: "@actions/languageserver",
      version: $version,
      license: "MIT",
      engines: {node: ">= 20"},
      repository: {url: "https://github.com/actions/languageservices"}
    }' >"$TOOL_FIXTURE/node_modules/@actions/languageserver/package.json"

  jq -n \
    --arg version "$TEST_VERSION" \
    --arg integrity "$TEST_INTEGRITY" \
    --arg platform_path "node_modules/@esbuild/$platform" \
    '{
      packages: {
        "node_modules/@actions/expressions": {
          version: $version,
          resolved: ("https://registry.npmjs.org/@actions/expressions/-/expressions-" + $version + ".tgz"),
          integrity: "sha512-expressions"
        },
        "node_modules/@actions/languageserver": {
          version: $version,
          resolved: ("https://registry.npmjs.org/@actions/languageserver/-/languageserver-" + $version + ".tgz"),
          integrity: $integrity
        },
        "node_modules/@actions/languageservice": {
          version: $version,
          resolved: ("https://registry.npmjs.org/@actions/languageservice/-/languageservice-" + $version + ".tgz"),
          integrity: "sha512-languageservice"
        },
        "node_modules/@actions/workflow-parser": {
          version: $version,
          resolved: ("https://registry.npmjs.org/@actions/workflow-parser/-/workflow-parser-" + $version + ".tgz"),
          integrity: "sha512-workflow-parser"
        },
        "node_modules/esbuild": {
          version: "0.27.1",
          resolved: "https://registry.npmjs.org/esbuild/-/esbuild-0.27.1.tgz",
          integrity: "sha512-esbuild"
        },
        ($platform_path): {
          version: "0.27.1",
          integrity: "sha512-platform",
          optional: true
        }
      }
    }' >"$TOOL_FIXTURE/package-lock.json"

  cat >"$TOOL_FIXTURE/node_modules/esbuild/bin/esbuild" <<'JS'
const { copyFileSync, mkdirSync } = require("node:fs");
const path = require("node:path");

if (process.argv.includes("--version")) {
  process.stdout.write("0.27.1\n");
  process.exit(0);
}
const output = process.argv.find((argument) => argument.startsWith("--outfile=")).slice(10);
const metafile = process.argv.find((argument) => argument.startsWith("--metafile=")).slice(11);
mkdirSync(path.dirname(output), { recursive: true });
copyFileSync(process.env.FIXTURE_BUNDLE, output);
copyFileSync(process.env.FIXTURE_METAFILE, metafile);
JS

  printf '#!%s\n' "$BASH_BIN" >"$MOCK_BIN/git"
  cat >>"$MOCK_BIN/git" <<'SH'
set -euo pipefail
if [[ ${1-} == rev-parse && ${2-} == --show-toplevel ]]; then
  printf '%s\n' "$REPO_ROOT"
elif [[ " $* " == *" clone "* ]]; then
  destination=${!#}
  cp -R "$SOURCE_FIXTURE/." "$destination"
elif [[ " $* " == *" checkout "* ]]; then
  exit 0
elif [[ " $* " == *" rev-parse HEAD "* ]]; then
  printf '%s\n' "$TEST_GIT_HEAD"
else
  printf 'unexpected git invocation: %s\n' "$*" >&2
  exit 1
fi
SH
  printf '#!%s\n' "$BASH_BIN" >"$MOCK_BIN/pnpm"
  cat >>"$MOCK_BIN/pnpm" <<'SH'
set -euo pipefail
case ${2-} in
  '@actions/languageserver@latest') file=languageserver.json ;;
  '@actions/expressions@'*) file=expressions.json ;;
  '@actions/languageservice@'*) file=languageservice.json ;;
  '@actions/workflow-parser@'*) file=workflow-parser.json ;;
  *) printf 'unexpected pnpm invocation: %s\n' "$*" >&2; exit 1 ;;
esac
cp "$METADATA_FIXTURE/$file" /dev/stdout
SH
  printf '#!%s\n' "$BASH_BIN" >"$MOCK_BIN/npm"
  cat >>"$MOCK_BIN/npm" <<'SH'
set -euo pipefail
case ${1-} in
  ci | audit) exit 0 ;;
  install)
    prefix=
    while (($#)); do
      if [[ $1 == --prefix ]]; then
        prefix=$2
        break
      fi
      shift
    done
    test -n "$prefix"
    cp -R "$TOOL_FIXTURE/node_modules" "$prefix/node_modules"
    cp "$TOOL_FIXTURE/package-lock.json" "$prefix/package-lock.json"
    ;;
  *) printf 'unexpected npm invocation: %s\n' "$*" >&2; exit 1 ;;
esac
SH
  printf '#!%s\n' "$BASH_BIN" >"$MOCK_BIN/nix"
  cat >>"$MOCK_BIN/nix" <<'SH'
set -euo pipefail
jq -n --arg storePath "$ARCHIVE" '{storePath: $storePath}'
SH
  chmod +x \
    "$MOCK_BIN/git" \
    "$MOCK_BIN/pnpm" \
    "$MOCK_BIN/npm" \
    "$MOCK_BIN/nix" \
    "$MOCK_BIN/openssl"

  printf '%s\n' '{"version":"1.2.3"}' \
    >"$REPO_ROOT/modules/features/ci/_packages/gha-diag/language-server.json"
}

@test "updater regenerates verified notices idempotently" {
  make_update_fixture
  local output_files=(
    "$REPO_ROOT/modules/features/ci/_packages/gha-diag/vendor/cli.bundle.cjs"
    "$REPO_ROOT/modules/features/ci/_packages/gha-diag/vendor/LICENSE"
    "$REPO_ROOT/modules/features/ci/_packages/gha-diag/vendor/LICENSE-THIRD-PARTY"
    "$REPO_ROOT/modules/features/ci/_packages/gha-diag/vendor/third-party-licenses.json"
    "$REPO_ROOT/modules/features/ci/_packages/gha-diag/language-server.json"
  )
  local test_path="$MOCK_BIN:$PATH"

  run env \
    PATH="$test_path" \
    REPO_ROOT="$REPO_ROOT" \
    SOURCE_FIXTURE="$SOURCE_FIXTURE" \
    TOOL_FIXTURE="$TOOL_FIXTURE" \
    METADATA_FIXTURE="$METADATA_FIXTURE" \
    TEST_GIT_HEAD="$TEST_GIT_HEAD" \
    FIXTURE_BUNDLE="$FIXTURE_BUNDLE" \
    FIXTURE_METAFILE="$FIXTURE_METAFILE" \
    ARCHIVE="$ARCHIVE" \
    "$BASH_BIN" "$UPDATE_SCRIPT"

  [ "$status" -eq 0 ]
  [ "$(jq -r '.version' "${output_files[4]}")" = "$TEST_VERSION" ]
  [ "$(jq -r '.bundleReproduction.byteForByte' "${output_files[4]}")" = true ]
  [ "$(jq -r '.registryVerification.sourceDependencies' "${output_files[4]}")" = true ]
  [ "$(jq -r '.registryVerification.reproductionDependencies' "${output_files[4]}")" = true ]
  [ "$(jq -r '.experimentalFeatures | join(",")' "${output_files[4]}")" = 'fixtureFeature,otherFixtureFeature' ]
  [ "$(jq -r '.schemaVersion' "${output_files[3]}")" = 'gha-diag-node-licenses-v2' ]
  sha256sum "${output_files[@]}" >"$BATS_TEST_TMPDIR/first-hashes"

  run env \
    PATH="$test_path" \
    REPO_ROOT="$REPO_ROOT" \
    SOURCE_FIXTURE="$SOURCE_FIXTURE" \
    TOOL_FIXTURE="$TOOL_FIXTURE" \
    METADATA_FIXTURE="$METADATA_FIXTURE" \
    TEST_GIT_HEAD="$TEST_GIT_HEAD" \
    FIXTURE_BUNDLE="$FIXTURE_BUNDLE" \
    FIXTURE_METAFILE="$FIXTURE_METAFILE" \
    ARCHIVE="$ARCHIVE" \
    "$BASH_BIN" "$UPDATE_SCRIPT"

  [ "$status" -eq 0 ]
  sha256sum "${output_files[@]}" >"$BATS_TEST_TMPDIR/second-hashes"
  cmp "$BATS_TEST_TMPDIR/first-hashes" "$BATS_TEST_TMPDIR/second-hashes"
}

@test "updater rejects an oversized bundle before changing outputs" {
  make_update_fixture
  head -c 16777217 /dev/zero \
    >"$BATS_TEST_TMPDIR/archive/package/dist/cli.bundle.cjs"
  tar -czf "$ARCHIVE" -C "$BATS_TEST_TMPDIR/archive" package

  run env \
    PATH="$MOCK_BIN:$PATH" \
    REPO_ROOT="$REPO_ROOT" \
    SOURCE_FIXTURE="$SOURCE_FIXTURE" \
    TOOL_FIXTURE="$TOOL_FIXTURE" \
    METADATA_FIXTURE="$METADATA_FIXTURE" \
    TEST_GIT_HEAD="$TEST_GIT_HEAD" \
    FIXTURE_BUNDLE="$FIXTURE_BUNDLE" \
    FIXTURE_METAFILE="$FIXTURE_METAFILE" \
    ARCHIVE="$ARCHIVE" \
    "$BASH_BIN" "$UPDATE_SCRIPT"

  [ "$status" -ne 0 ]
  [[ "$output" == *"language server bundle exceeds the 16 MiB extraction limit"* ]]
  [ "$(jq -r .version "$REPO_ROOT/modules/features/ci/_packages/gha-diag/language-server.json")" = '1.2.3' ]
  [ ! -e "$REPO_ROOT/modules/features/ci/_packages/gha-diag/vendor/cli.bundle.cjs" ]
}

@test "updater restores every output when the final commit fails" {
  make_update_fixture
  local package_dir="$REPO_ROOT/modules/features/ci/_packages/gha-diag"
  local output_files=(
    "$package_dir/vendor/cli.bundle.cjs"
    "$package_dir/vendor/LICENSE"
    "$package_dir/vendor/LICENSE-THIRD-PARTY"
    "$package_dir/vendor/third-party-licenses.json"
    "$package_dir/language-server.json"
  )
  local real_mv
  real_mv=$(command -v mv)
  printf '%s\n' old-bundle >"${output_files[0]}"
  printf '%s\n' old-license >"${output_files[1]}"
  printf '%s\n' old-third-party >"${output_files[2]}"
  printf '%s\n' old-inventory >"${output_files[3]}"
  printf '%s\n' '{"version":"1.2.3"}' >"${output_files[4]}"
  sha256sum "${output_files[@]}" >"$BATS_TEST_TMPDIR/before-failure"

  printf '#!%s\n' "$BASH_BIN" >"$MOCK_BIN/mv"
  cat >>"$MOCK_BIN/mv" <<'SH'
set -euo pipefail
if [[ ${GHA_DIAG_FAIL_COMMIT-} == true && ${1-} == *.update.* && ${1-} != *.backup && ${2-} == */vendor/LICENSE ]]; then
  exit 75
fi
exec "$REAL_MV" "$@"
SH
  chmod +x "$MOCK_BIN/mv"

  run env \
    PATH="$MOCK_BIN:$PATH" \
    REPO_ROOT="$REPO_ROOT" \
    SOURCE_FIXTURE="$SOURCE_FIXTURE" \
    TOOL_FIXTURE="$TOOL_FIXTURE" \
    METADATA_FIXTURE="$METADATA_FIXTURE" \
    TEST_GIT_HEAD="$TEST_GIT_HEAD" \
    FIXTURE_BUNDLE="$FIXTURE_BUNDLE" \
    FIXTURE_METAFILE="$FIXTURE_METAFILE" \
    ARCHIVE="$ARCHIVE" \
    GHA_DIAG_FAIL_COMMIT=true \
    REAL_MV="$real_mv" \
    "$BASH_BIN" "$UPDATE_SCRIPT"

  [ "$status" -eq 75 ]
  sha256sum "${output_files[@]}" >"$BATS_TEST_TMPDIR/after-failure"
  cmp "$BATS_TEST_TMPDIR/before-failure" "$BATS_TEST_TMPDIR/after-failure"
  shopt -s nullglob
  local leftovers=("$package_dir"/.*.update.* "$package_dir/vendor"/.*.update.*)
  [ "${#leftovers[@]}" -eq 0 ]
}

@test "updater defers TERM received between rename and state recording" {
  make_update_fixture
  local package_dir="$REPO_ROOT/modules/features/ci/_packages/gha-diag"
  local real_mv
  real_mv=$(command -v mv)

  printf '#!%s\n' "$BASH_BIN" >"$MOCK_BIN/mv"
  cat >>"$MOCK_BIN/mv" <<'SH'
set -euo pipefail
if [[ ${GHA_DIAG_SIGNAL_AFTER_RENAME-} == true && ${1-} == *.update.* && ${1-} != *.backup && ${2-} == */vendor/cli.bundle.cjs ]]; then
  "$REAL_MV" "$@"
  kill -TERM "$PPID"
  exit 0
fi
exec "$REAL_MV" "$@"
SH
  chmod +x "$MOCK_BIN/mv"

  run env \
    PATH="$MOCK_BIN:$PATH" \
    REPO_ROOT="$REPO_ROOT" \
    SOURCE_FIXTURE="$SOURCE_FIXTURE" \
    TOOL_FIXTURE="$TOOL_FIXTURE" \
    METADATA_FIXTURE="$METADATA_FIXTURE" \
    TEST_GIT_HEAD="$TEST_GIT_HEAD" \
    FIXTURE_BUNDLE="$FIXTURE_BUNDLE" \
    FIXTURE_METAFILE="$FIXTURE_METAFILE" \
    ARCHIVE="$ARCHIVE" \
    GHA_DIAG_SIGNAL_AFTER_RENAME=true \
    REAL_MV="$real_mv" \
    "$BASH_BIN" "$UPDATE_SCRIPT"

  [ "$status" -eq 143 ]
  cmp "$FIXTURE_BUNDLE" "$package_dir/vendor/cli.bundle.cjs"
  [ "$(jq -r .version "$package_dir/language-server.json")" = "$TEST_VERSION" ]
  [ "$(jq -r '.registryVerification.reproductionDependencies' "$package_dir/language-server.json")" = true ]
  [ "$(jq -r .schemaVersion "$package_dir/vendor/third-party-licenses.json")" = 'gha-diag-node-licenses-v2' ]
  shopt -s nullglob
  local leftovers=("$package_dir"/.*.update.* "$package_dir/vendor"/.*.update.*)
  [ "${#leftovers[@]}" -eq 0 ]
}

@test "updater rejects a non-semver language server release" {
  cat >"$MOCK_BIN/pnpm" <<EOF
#!$BASH_BIN
cat <<'JSON'
{
  "name": "@actions/languageserver",
  "version": "latest",
  "engines": { "node": ">= 20" },
  "repository": { "url": "git+https://github.com/actions/languageservices.git" },
  "gitHead": "b71ac284fc6a7382c22ecbf3e0009a6ae216823b",
  "time": {
    "latest": "2026-08-04T19:25:30.652Z",
    "modified": "2026-08-04T19:25:31.004Z"
  },
  "dist": {
    "integrity": "sha512-placeholder",
    "tarball": "https://registry.npmjs.org/@actions/languageserver/-/languageserver-latest.tgz",
    "attestations": {
      "url": "https://registry.npmjs.org/attestation",
      "provenance": { "predicateType": "https://slsa.dev/provenance/v1" }
    },
    "signatures": [{ "keyid": "SHA256:key" }]
  }
}
JSON
EOF
  chmod +x "$MOCK_BIN/pnpm"

  run env PATH="$MOCK_BIN:$PATH" bash "$UPDATE_SCRIPT"

  [ "$status" -ne 0 ]
  [[ "$output" == *"unsupported language server version"* ]]
}
