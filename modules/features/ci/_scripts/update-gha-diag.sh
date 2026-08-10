#!/usr/bin/env bash

set -euo pipefail

fail() {
  printf 'gha-diag: %s\n' "$1" >&2
  exit 1
}

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

package=@actions/languageserver
package_dir=modules/features/ci/_packages/gha-diag
registry=https://registry.npmjs.org/
feature_extractor=${GHA_DIAG_EXPERIMENTAL_FEATURE_EXTRACTOR:-modules/features/ci/_scripts/extract-gha-diag-experimental-features.mjs}
metadata=$(pnpm view "$package@latest" --json --registry="$registry")

name=$(jq -er .name <<<"$metadata")
version=$(jq -er .version <<<"$metadata")
node_engine=$(jq -er .engines.node <<<"$metadata")
integrity=$(jq -er .dist.integrity <<<"$metadata")
tarball=$(jq -er .dist.tarball <<<"$metadata")
repository=$(jq -er 'if (.repository | type) == "object" then .repository.url else .repository end' <<<"$metadata")
git_head=$(jq -er .gitHead <<<"$metadata")
published_at=$(jq -er --arg version "$version" '.time[$version]' <<<"$metadata")
deprecated=$(jq -r '.deprecated // empty' <<<"$metadata")
attestation=$(jq -er .dist.attestations.url <<<"$metadata")
predicate_type=$(jq -er .dist.attestations.provenance.predicateType <<<"$metadata")
signature_key_id=$(jq -er '.dist.signatures | select(length > 0) | .[0].keyid' <<<"$metadata")

if [[ $name != "$package" ]]; then
  fail "unexpected npm package identity: $name"
fi
if [[ ${#version} -gt 64 || ! $version =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  fail "unsupported language server version: $version"
fi
if [[ ! $node_engine =~ ^\>=[[:space:]]*20$ ]]; then
  fail "upstream Node.js requirement needs review: $node_engine"
fi
if [[ -n $deprecated ]]; then
  fail "refusing deprecated language server release: $deprecated"
fi

current_version=$(jq -er .version "$package_dir/language-server.json")
oldest_version=$(printf '%s\n%s\n' "$current_version" "$version" | sort -V | head -n1)
if [[ $version != "$current_version" && $oldest_version != "$current_version" ]]; then
  fail "refusing language server downgrade: $current_version -> $version"
fi
if [[ $repository != "git+https://github.com/actions/languageservices.git" && $repository != "https://github.com/actions/languageservices.git" ]]; then
  fail "unexpected upstream repository: $repository"
fi
if [[ ! $git_head =~ ^[0-9a-f]{40}$ ]]; then
  fail "invalid upstream gitHead: $git_head"
fi
if [[ $predicate_type != "https://slsa.dev/provenance/v1" ]]; then
  fail "unsupported provenance predicate: $predicate_type"
fi
if [[ $tarball != "https://registry.npmjs.org/@actions/languageserver/-/languageserver-$version.tgz" ]]; then
  fail "unexpected npm tarball URL: $tarball"
fi
if [[ $integrity != sha512-* ]]; then
  fail "npm artifact has no SHA-512 integrity"
fi

temporary=$(mktemp -d "${TMPDIR:-/tmp}/update-gha-diag.XXXXXX")
commit_started=false
commit_completed=false
deferred_signal=0
stage_paths=()
final_paths=()
backup_paths=()
new_moved=()

cleanup() {
  local status=$?
  local rollback_failed=false
  local index
  local stage
  trap - EXIT INT TERM
  if [[ $commit_started == true && $commit_completed != true ]]; then
    set +e
    for index in "${!final_paths[@]}"; do
      if [[ -e ${backup_paths[$index]} ]]; then
        mv "${backup_paths[$index]}" "${final_paths[$index]}" || rollback_failed=true
      elif [[ ${new_moved[$index]} == true ]]; then
        rm -f "${final_paths[$index]}" || rollback_failed=true
      fi
    done
    set -e
  fi
  for stage in "${stage_paths[@]}"; do
    rm -f "$stage"
  done
  if [[ $commit_completed == true || $rollback_failed == false ]]; then
    rm -f "${backup_paths[@]}"
  else
    printf 'gha-diag: rollback failed; preserving adjacent backup files\n' >&2
    status=1
  fi
  rm -rf "$temporary"
  exit "$status"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

defer_signal() {
  deferred_signal=$1
}

source_checkout="$temporary/languageservices"
mkdir -p "$temporary/home"
GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null git \
  -c core.hooksPath=/dev/null \
  clone --filter=blob:none --no-checkout \
  https://github.com/actions/languageservices.git "$source_checkout"
GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null git \
  -C "$source_checkout" -c core.hooksPath=/dev/null \
  checkout --detach "$git_head"
test "$(git -C "$source_checkout" rev-parse HEAD)" = "$git_head"
test "$(jq -er .version "$source_checkout/languageserver/package.json")" = "$version"

package_lock_sha256=$(sha256sum "$source_checkout/package-lock.json" | cut -d ' ' -f 1)
HOME="$temporary/home" \
  npm_config_cache="$temporary/npm-cache" \
  npm_config_userconfig=/dev/null \
  npm ci \
  --prefix "$source_checkout" \
  --ignore-scripts \
  --omit=dev \
  --no-audit \
  --no-fund \
  --registry="$registry"
test "$(sha256sum "$source_checkout/package-lock.json" | cut -d ' ' -f 1)" = "$package_lock_sha256"
HOME="$temporary/home" \
  npm_config_cache="$temporary/npm-cache" \
  npm_config_userconfig=/dev/null \
  npm audit signatures \
  --prefix "$source_checkout" \
  --registry="$registry"

prefetched=$(nix store prefetch-file --json "$tarball")
archive=$(jq -er .storePath <<<"$prefetched")
test "$(wc -c <"$archive")" -le 33554432
actual_integrity="sha512-$(openssl dgst -sha512 -binary "$archive" | base64 --wrap=0)"
if [[ $actual_integrity != "$integrity" ]]; then
  fail "npm artifact integrity mismatch"
fi

test "$(tar -tf "$archive" | grep -Fxc 'package/dist/cli.bundle.cjs')" -eq 1
test "$(tar -tf "$archive" | grep -Fxc 'package/LICENSE')" -eq 1
if ! tar -xOf "$archive" package/dist/cli.bundle.cjs |
  head -c 16777217 >"$temporary/published-cli.bundle.cjs"; then
  fail "cannot safely extract the language server bundle"
fi
if ! tar -xOf "$archive" package/LICENSE |
  head -c 1048577 >"$temporary/LICENSE"; then
  fail "cannot safely extract the upstream license"
fi
test -s "$temporary/published-cli.bundle.cjs"
if [[ $(wc -c <"$temporary/published-cli.bundle.cjs") -gt 16777216 ]]; then
  fail "language server bundle exceeds the 16 MiB extraction limit"
fi
test -s "$temporary/LICENSE"
if [[ $(wc -c <"$temporary/LICENSE") -gt 1048576 ]]; then
  fail "upstream license exceeds the 1 MiB extraction limit"
fi
grep -Fq 'actions/readFile' "$temporary/published-cli.bundle.cjs"

esbuild_version=$(jq -er '.packages["node_modules/esbuild"].version' "$source_checkout/package-lock.json")
esbuild_integrity=$(jq -er '.packages["node_modules/esbuild"].integrity' "$source_checkout/package-lock.json")
esbuild_resolved=$(jq -er '.packages["node_modules/esbuild"].resolved' "$source_checkout/package-lock.json")
if [[ ${#esbuild_version} -gt 64 || ! $esbuild_version =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  fail "unsupported esbuild version: $esbuild_version"
fi
if [[ $esbuild_integrity != sha512-* || $esbuild_resolved != "https://registry.npmjs.org/esbuild/-/esbuild-$esbuild_version.tgz" ]]; then
  fail "untrusted esbuild lock entry"
fi

platform=$(node -p 'process.platform + "-" + process.arch')
case "$platform" in
darwin-arm64 | darwin-x64 | linux-arm64 | linux-x64) ;;
*) fail "unsupported esbuild platform: $platform" ;;
esac
platform_lock_path="node_modules/@esbuild/$platform"
platform_integrity=$(jq -er --arg path "$platform_lock_path" '.packages[$path].integrity' "$source_checkout/package-lock.json")
if ! jq -e \
  --arg path "$platform_lock_path" \
  --arg version "$esbuild_version" \
  --arg os "${platform%-*}" \
  --arg cpu "${platform#*-}" \
  '.packages[$path] | .version == $version and .optional == true and .os == [$os] and .cpu == [$cpu] and (.integrity | startswith("sha512-"))' \
  "$source_checkout/package-lock.json" >/dev/null; then
  fail "invalid esbuild platform lock entry: $platform"
fi

internal_packages=(expressions workflow-parser languageservice)
for unscoped in "${internal_packages[@]}"; do
  internal_name="@actions/$unscoped"
  internal_metadata="$temporary/$unscoped-metadata.json"
  pnpm view "$internal_name@$version" --json --registry="$registry" >"$internal_metadata"
  expected_tarball="https://registry.npmjs.org/@actions/$unscoped/-/$unscoped-$version.tgz"
  if ! jq -e \
    --arg name "$internal_name" \
    --arg version "$version" \
    --arg git_head "$git_head" \
    --arg tarball "$expected_tarball" \
    '
      .name == $name and
      .version == $version and
      .license == "MIT" and
      .engines.node == ">= 20" and
      ((if (.repository | type) == "object" then .repository.url else .repository end) |
        sub("^git\\+"; "") | sub("\\.git$"; "")) ==
        "https://github.com/actions/languageservices" and
      .gitHead == $git_head and
      .dist.tarball == $tarball and
      (.dist.integrity | startswith("sha512-")) and
      .dist.attestations.provenance.predicateType == "https://slsa.dev/provenance/v1" and
      (.dist.signatures | length) > 0
    ' "$internal_metadata" >/dev/null; then
    fail "untrusted npm metadata for $internal_name@$version"
  fi
done

reproduction_tool="$temporary/reproduction-tool"
mkdir -p "$reproduction_tool"
jq -n \
  --arg version "$version" \
  --arg esbuild_version "$esbuild_version" \
  '{
    private: true,
    dependencies: {
      "@actions/expressions": $version,
      "@actions/languageserver": $version,
      "@actions/languageservice": $version,
      "@actions/workflow-parser": $version,
      esbuild: $esbuild_version
    }
  }' >"$reproduction_tool/package.json"
HOME="$temporary/home" \
  npm_config_cache="$temporary/npm-cache" \
  npm_config_userconfig=/dev/null \
  npm install \
  --prefix "$reproduction_tool" \
  --ignore-scripts \
  --no-audit \
  --no-fund \
  --registry="$registry"
HOME="$temporary/home" \
  npm_config_cache="$temporary/npm-cache" \
  npm_config_userconfig=/dev/null \
  npm audit signatures \
  --prefix "$reproduction_tool" \
  --registry="$registry"

if ! jq -e \
  --arg version "$version" \
  --arg integrity "$integrity" \
  --arg tarball "$tarball" \
  '.packages["node_modules/@actions/languageserver"] | .version == $version and .integrity == $integrity and .resolved == $tarball' \
  "$reproduction_tool/package-lock.json" >/dev/null; then
  fail "installed language server does not match registry metadata"
fi
if ! jq -e \
  --arg version "$version" \
  '
    .name == "@actions/languageserver" and
    .version == $version and
    .license == "MIT" and
    .engines.node == ">= 20" and
    ((if (.repository | type) == "object" then .repository.url else .repository end) |
      sub("^git\\+"; "") | sub("\\.git$"; "")) ==
      "https://github.com/actions/languageservices"
  ' "$reproduction_tool/node_modules/@actions/languageserver/package.json" >/dev/null; then
  fail "installed language server manifest mismatch"
fi
cmp "$temporary/published-cli.bundle.cjs" \
  "$reproduction_tool/node_modules/@actions/languageserver/dist/cli.bundle.cjs"
cmp "$temporary/LICENSE" \
  "$reproduction_tool/node_modules/@actions/languageserver/LICENSE"

if ! jq -e \
  --arg version "$esbuild_version" \
  --arg integrity "$esbuild_integrity" \
  --arg resolved "$esbuild_resolved" \
  '.packages["node_modules/esbuild"] | .version == $version and .integrity == $integrity and .resolved == $resolved' \
  "$reproduction_tool/package-lock.json" >/dev/null; then
  fail "installed esbuild does not match the upstream lock"
fi
if ! jq -e \
  --arg path "$platform_lock_path" \
  --arg version "$esbuild_version" \
  --arg integrity "$platform_integrity" \
  '.packages[$path] | .version == $version and .integrity == $integrity and .optional == true' \
  "$reproduction_tool/package-lock.json" >/dev/null; then
  fail "installed esbuild platform binary does not match the upstream lock"
fi

for unscoped in "${internal_packages[@]}"; do
  internal_name="@actions/$unscoped"
  internal_metadata="$temporary/$unscoped-metadata.json"
  internal_integrity=$(jq -er .dist.integrity "$internal_metadata")
  internal_tarball=$(jq -er .dist.tarball "$internal_metadata")
  internal_lock_path="node_modules/$internal_name"
  if ! jq -e \
    --arg path "$internal_lock_path" \
    --arg version "$version" \
    --arg integrity "$internal_integrity" \
    --arg tarball "$internal_tarball" \
    '.packages[$path] | .version == $version and .integrity == $integrity and .resolved == $tarball' \
    "$reproduction_tool/package-lock.json" >/dev/null; then
    fail "installed package does not match registry metadata: $internal_name"
  fi
  installed_package="$reproduction_tool/node_modules/$internal_name"
  if ! jq -e \
    --arg name "$internal_name" \
    --arg version "$version" \
    '
      .name == $name and
      .version == $version and
      .license == "MIT" and
      .engines.node == ">= 20" and
      ((if (.repository | type) == "object" then .repository.url else .repository end) |
        sub("^git\\+"; "") | sub("\\.git$"; "")) ==
        "https://github.com/actions/languageservices"
    ' "$installed_package/package.json" >/dev/null; then
    fail "installed package manifest mismatch: $internal_name"
  fi
  test -s "$installed_package/LICENSE"
  test -d "$installed_package/dist"
  test ! -e "$source_checkout/$unscoped/dist"
  cp -R "$installed_package/dist" "$source_checkout/$unscoped/dist"
done

experimental_features=$(node "$feature_extractor" \
  "$reproduction_tool/node_modules/@actions/expressions/dist/index.js")
if ! jq -e 'type == "array" and all(.[]; type == "string")' \
  <<<"$experimental_features" >/dev/null; then
  fail "invalid experimental feature inventory"
fi

esbuild="$reproduction_tool/node_modules/esbuild/bin/esbuild"
test "$(node "$esbuild" --version)" = "$esbuild_version"
mkdir -p "$source_checkout/languageserver/dist"
(
  cd "$source_checkout/languageserver"
  node "$esbuild" \
    src/index.ts \
    --bundle \
    --platform=node \
    --format=cjs \
    --outfile=dist/cli.bundle.cjs \
    --metafile="$temporary/esbuild-metafile.json"
)
if ! cmp -s \
  "$temporary/published-cli.bundle.cjs" \
  "$source_checkout/languageserver/dist/cli.bundle.cjs"; then
  fail "rebuilt bundle does not match the published npm artifact"
fi

node "$repo_root/modules/features/ci/_scripts/generate-gha-diag-node-licenses.mjs" \
  "$source_checkout" \
  "$temporary/published-cli.bundle.cjs" \
  "$source_checkout/languageserver/dist/cli.bundle.cjs" \
  "$temporary/esbuild-metafile.json" \
  "$temporary/LICENSE-THIRD-PARTY" \
  "$temporary/third-party-licenses.json"
bundle_sha256=$(sha256sum "$temporary/published-cli.bundle.cjs" | cut -d ' ' -f 1)
node_licenses_sha256=$(sha256sum "$temporary/LICENSE-THIRD-PARTY" | cut -d ' ' -f 1)
node_licenses_inventory_sha256=$(sha256sum "$temporary/third-party-licenses.json" | cut -d ' ' -f 1)

jq -n \
  --arg package "$package" \
  --arg version "$version" \
  --arg node_engine "$node_engine" \
  --arg integrity "$integrity" \
  --arg tarball "$tarball" \
  --arg repository "https://github.com/actions/languageservices.git" \
  --arg git_head "$git_head" \
  --arg published_at "$published_at" \
  --arg attestation "$attestation" \
  --arg predicate_type "$predicate_type" \
  --arg signature_key_id "$signature_key_id" \
  --arg package_lock_sha256 "$package_lock_sha256" \
  --arg esbuild_version "$esbuild_version" \
  --arg bundle_sha256 "$bundle_sha256" \
  --arg node_licenses_sha256 "$node_licenses_sha256" \
  --arg node_licenses_inventory_sha256 "$node_licenses_inventory_sha256" \
  --argjson experimental_features "$experimental_features" \
  '{
    package: $package,
    version: $version,
    engines: { node: $node_engine },
    integrity: $integrity,
    tarball: $tarball,
    repository: $repository,
    gitHead: $git_head,
    publishedAt: $published_at,
    attestation: $attestation,
    provenancePredicateType: $predicate_type,
    registrySignatureKeyId: $signature_key_id,
    upstreamPackageLockSha256: $package_lock_sha256,
    registryVerification: {
      sourceDependencies: true,
      reproductionDependencies: true
    },
    bundleReproduction: {
      byteForByte: true,
      esbuildVersion: $esbuild_version
    },
    experimentalFeatures: $experimental_features,
    bundleSha256: $bundle_sha256,
    nodeLicensesSha256: $node_licenses_sha256,
    nodeLicensesInventorySha256: $node_licenses_inventory_sha256
  }' >"$temporary/language-server.json"

stage_output() {
  local source=$1
  local destination=$2
  local directory
  local basename
  local stage
  directory=$(dirname "$destination")
  basename=$(basename "$destination")
  stage=$(mktemp "$directory/.$basename.update.XXXXXX")
  stage_paths+=("$stage")
  final_paths+=("$destination")
  backup_paths+=("$stage.backup")
  new_moved+=(false)
  install -m644 "$source" "$stage"
}

stage_output "$temporary/published-cli.bundle.cjs" "$package_dir/vendor/cli.bundle.cjs"
stage_output "$temporary/LICENSE" "$package_dir/vendor/LICENSE"
stage_output "$temporary/LICENSE-THIRD-PARTY" "$package_dir/vendor/LICENSE-THIRD-PARTY"
stage_output "$temporary/third-party-licenses.json" "$package_dir/vendor/third-party-licenses.json"
# Metadata is staged and committed last so it remains the consistency marker.
stage_output "$temporary/language-server.json" "$package_dir/language-server.json"

# A signal between rename(2) and the following shell assignment would otherwise
# make rollback state ambiguous. Finish or roll back the small commit section
# before honoring INT/TERM; SIGKILL remains outside the shell's control.
trap 'defer_signal 130' INT
trap 'defer_signal 143' TERM
for index in "${!final_paths[@]}"; do
  if [[ -e ${final_paths[$index]} ]]; then
    cp -p "${final_paths[$index]}" "${backup_paths[$index]}"
  fi
done
commit_started=true
for index in "${!final_paths[@]}"; do
  mv "${stage_paths[$index]}" "${final_paths[$index]}"
  new_moved[index]=true
done
commit_completed=true
trap 'exit 130' INT
trap 'exit 143' TERM
if ((deferred_signal != 0)); then
  exit "$deferred_signal"
fi
