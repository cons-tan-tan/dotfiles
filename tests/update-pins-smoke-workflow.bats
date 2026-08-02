#!/usr/bin/env bats

setup() {
  REPO_ROOT=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
  WORKFLOW="$REPO_ROOT/.github/workflows/update-pins-smoke.yaml"
  CI_WORKFLOW="$REPO_ROOT/.github/workflows/ci.yaml"
  CACHE_GC_WORKFLOW="$REPO_ROOT/.github/workflows/cache-gc.yaml"
  CACHE_SETTINGS="$REPO_ROOT/nix/lib/cache-settings.nix"
}

normalize_lines() {
  sed \
    -e ':join' \
    -e '/\\$/ { N; s/\\\n[[:space:]]*/ /; b join; }' \
    -e 's/^[[:space:]]*//' \
    -e 's/[[:space:]]*$//' \
    -e 's/[[:space:]][[:space:]]*/ /g' \
    -e '/^$/d'
}

step_script() {
  local name=$1
  yq -r ".jobs.smoke.steps[] | select(.name == \"$name\") | .run" "$WORKFLOW"
}

ci_step_script() {
  local job=$1
  local name=$2
  yq -r ".jobs.\"$job\".steps[] | select(.name == \"$name\") | .run" "$CI_WORKFLOW"
}

cache_setting() {
  local name=$1
  local environment_name
  case "$name" in
    nixCommunitySubstituter) environment_name=CACHE_NIX_COMMUNITY_SUBSTITUTER ;;
    nixCommunityTrustedPublicKey) environment_name=CACHE_NIX_COMMUNITY_TRUSTED_PUBLIC_KEY ;;
    numtideSubstituter) environment_name=CACHE_NUMTIDE_SUBSTITUTER ;;
    numtideTrustedPublicKey) environment_name=CACHE_NUMTIDE_TRUSTED_PUBLIC_KEY ;;
    *) return 1 ;;
  esac

  if [[ -n "${!environment_name:-}" ]]; then
    printf '%s\n' "${!environment_name}"
  else
    sed -n "s/^[[:space:]]*$name = \"\([^\"]*\)\";.*/\1/p" "$CACHE_SETTINGS"
  fi
}

@test "upstream smoke workflow is weekly and manual only" {
  run yq -e '
    (.on.schedule | length) == 1
    and .on.schedule[0].cron == "37 4 * * 1"
    and (.on | keys | sort | join(",")) == "schedule,workflow_dispatch"
  ' "$WORKFLOW"
  [ "$status" -eq 0 ]

  run yq -e '
    (.on | has("workflow_dispatch"))
    and .on.push == null
    and .on.pull_request == null
  ' "$WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "upstream smoke workflow has a bounded read-only job" {
  run yq -e '
    .permissions.contents == "read"
    and (.permissions | length) == 1
    and .jobs.smoke.permissions == null
    and .concurrency.group == "update-pins-upstream-smoke"
    and .concurrency.cancel-in-progress == true
    and .jobs.smoke.timeout-minutes == 20
    and ([.jobs.smoke.steps[] | select(
      .name == "Create disposable updater checkout"
    )][0].env.UPDATE_PINS_CHECKOUT)
      == "${{ runner.temp }}/update-pins-check"
    and .jobs.smoke.steps[0].uses
      == "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1"
    and .jobs.smoke.steps[0].with."persist-credentials" == false
  ' "$WORKFLOW"
  [ "$status" -eq 0 ]

  ! grep -Fq 'continue-on-error:' "$WORKFLOW"
}

@test "upstream smoke workflow reuses pinned CI actions" {
  local -a actions
  local action
  mapfile -t actions < <(
    yq -r '.jobs.smoke.steps[].uses // "" | select(length > 0)' "$WORKFLOW"
  )
  [ "${#actions[@]}" -eq 3 ]
  for action in "${actions[@]}"; do
    [[ "$action" =~ ^[^@]+@[0-9a-f]{40}$ ]] || return 1
    grep -Fq "uses: $action" "$CI_WORKFLOW" || return 1
  done
}

@test "all workflow checkouts disable credential persistence" {
  local workflow
  local count=0
  for workflow in "$CI_WORKFLOW" "$CACHE_GC_WORKFLOW" "$WORKFLOW"; do
    run yq -e '
      [.jobs[].steps[]? | select(
        (.uses // "") | test("^actions/checkout@")
      )] as $checkouts
      | ($checkouts | length) > 0
        and ([$checkouts[] | .with."persist-credentials" == false] | all)
    ' "$workflow"
    [ "$status" -eq 0 ]
    checkout_count="$(yq -r '[.jobs[].steps[]? | select(
      (.uses // "") | test("^actions/checkout@")
    )] | length' "$workflow")"
    count=$((count + checkout_count))
  done
  [ "$count" -gt 0 ]
}

@test "live contract executable crosses the expression boundary through env" {
  run yq -e '
    [
      ([.jobs.smoke.steps[] | select(
        .name == "Check live upstream contracts"
      )][0].env.UPDATE_PINS_SMOKE
        == "${{ steps.build.outputs.path }}/bin/update-pins-smoke"),
      ([.jobs.smoke.steps[] | select(
        .name == "Check live upstream contracts"
      )][0].run | contains("${{ steps.build.outputs.path }}") | not),
      ([.jobs.smoke.steps[] | select(
        .name == "Check live upstream contracts"
      )][0].run | contains("\"$UPDATE_PINS_SMOKE\""))
    ] | all
  ' "$WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "Hestia workflow inputs stay aligned with the CI defaults" {
  local version
  local upstream_key_names
  version=$(yq -r '.env.HESTIA_VERSION' "$CI_WORKFLOW")
  upstream_key_names=$(yq -r '.env.HESTIA_UPSTREAM_CACHE_KEY_NAMES' "$CI_WORKFLOW")

  [ "$(yq -r '.jobs.smoke.steps[] | select(.uses == "Mic92/hestia@b21a1aaf8c3d5c2e430c9ba278c0f78abd46a320") | .with.version' "$WORKFLOW")" = "$version" ]
  [ "$(yq -r '.jobs.smoke.steps[] | select(.uses == "Mic92/hestia@b21a1aaf8c3d5c2e430c9ba278c0f78abd46a320") | .with."upstream-cache-filter"' "$WORKFLOW")" = true ]
  [ "$(yq -r '.jobs.smoke.steps[] | select(.uses == "Mic92/hestia@b21a1aaf8c3d5c2e430c9ba278c0f78abd46a320") | .with."upstream-cache-key-names"' "$WORKFLOW")" = "$upstream_key_names" ]
  [ "$(yq -r '.jobs.gc.steps[] | select(.uses == "Mic92/hestia@b21a1aaf8c3d5c2e430c9ba278c0f78abd46a320") | .with.version' "$CACHE_GC_WORKFLOW")" = "$version" ]
}

@test "Linux checks are evaluated once for the Hestia matrix" {
  run yq -e '
    .jobs."build-linux-eval".runs-on == "ubuntu-latest"
    and .jobs."build-linux-eval".outputs.matrix
      == "${{ steps.matrix.outputs.matrix }}"
    and .jobs."build-linux-eval".outputs."any-jobs"
      == "${{ steps.matrix.outputs.any-jobs }}"
    and .jobs."build-linux-eval".outputs."manifest-version"
      == "${{ steps.matrix.outputs.manifest-version }}"
    and ([.jobs."build-linux-eval".steps[] | select(.id == "matrix")]
      | length) == 1
    and ([.jobs."build-linux-eval".steps[] | select(.id == "matrix")][0].uses)
      == "Mic92/hestia/matrix@b21a1aaf8c3d5c2e430c9ba278c0f78abd46a320"
    and ([.jobs."build-linux-eval".steps[] | select(.id == "matrix")][0].with.flake)
      == ".#checks.x86_64-linux"
    and ([.jobs."build-linux-eval".steps[] | select(
      .name == "Install matrix evaluator"
    )][0].run) == "nix profile add --inputs-from . nixpkgs#nix-eval-jobs"
  ' "$CI_WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "Linux matrix waits for and builds the evaluated derivations" {
  run yq -e '
    .jobs."build-linux-matrix".needs == "build-linux-eval"
    and .jobs."build-linux-matrix".if
      == "needs.build-linux-eval.outputs.any-jobs == '\''true'\''"
    and .jobs."build-linux-matrix".strategy."fail-fast" == false
    and .jobs."build-linux-matrix".strategy."max-parallel" == 5
    and .jobs."build-linux-matrix".strategy.matrix
      == "${{ fromJSON(needs.build-linux-eval.outputs.matrix) }}"
    and ([.jobs."build-linux-matrix".steps[] | select(
      .uses == "Mic92/hestia@b21a1aaf8c3d5c2e430c9ba278c0f78abd46a320"
    )][0].with."wait-manifest-version")
      == "${{ needs.build-linux-eval.outputs.manifest-version }}"
    and ([.jobs."build-linux-matrix".steps[] | select(
      .name == "Prefetch derivation closure and build"
    )][0].env.INSTALLABLES) == "${{ matrix.installables }}"
    and ([.jobs."build-linux-matrix".steps[] | select(
      .name == "Prefetch derivation closure and build"
    )][0].run | contains("/closure/$hashes"))
    and ([.jobs."build-linux-matrix".steps[] | select(
      .name == "Prefetch derivation closure and build"
    )][0].run | contains("nix-store --import"))
    and ([.jobs."build-linux-matrix".steps[] | select(
      .name == "Prefetch derivation closure and build"
    )][0].run | contains("nix build"))
  ' "$CI_WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "Linux matrix keeps public substituters and a stable aggregate result" {
  local numtide_substituter
  local numtide_key
  local nix_community_substituter
  local nix_community_key
  local expected_substituters
  local expected_keys
  local expected_hestia_key_names
  numtide_substituter=$(cache_setting numtideSubstituter)
  numtide_key=$(cache_setting numtideTrustedPublicKey)
  nix_community_substituter=$(cache_setting nixCommunitySubstituter)
  nix_community_key=$(cache_setting nixCommunityTrustedPublicKey)
  expected_substituters="$numtide_substituter $nix_community_substituter"
  expected_keys="$numtide_key $nix_community_key"
  expected_hestia_key_names="cache.nixos.org-1 ${numtide_key%%:*} ${nix_community_key%%:*}"

  run env \
    EXPECTED_SUBSTITUTERS="$expected_substituters" \
    EXPECTED_KEYS="$expected_keys" \
    EXPECTED_HESTIA_KEY_NAMES="$expected_hestia_key_names" \
    yq -e '
      .env.NIX_EXTRA_SUBSTITUTERS == strenv(EXPECTED_SUBSTITUTERS)
      and .env.NIX_EXTRA_TRUSTED_PUBLIC_KEYS == strenv(EXPECTED_KEYS)
      and .env.HESTIA_VERSION == "v3.0.0"
      and .env.HESTIA_UPSTREAM_CACHE_KEY_NAMES
        == strenv(EXPECTED_HESTIA_KEY_NAMES)
    ' "$CI_WORKFLOW"
  [ "$status" -eq 0 ]

  run yq -e '
    ([
      .jobs."build-linux-eval".steps[],
      .jobs."build-linux-matrix".steps[]
    ] | map(select(.uses
      == "nixbuild/nix-quick-install-action@9f63be77f412a248c9d9a65a4c82cf066cdf8f0c"))
      | length) == 2
    and ([
      .jobs."build-linux-eval".steps[],
      .jobs."build-linux-matrix".steps[]
    ] | map(select(.uses
      == "nixbuild/nix-quick-install-action@9f63be77f412a248c9d9a65a4c82cf066cdf8f0c"))
      | map(select(.with.nix_conf | contains("${{ env.NIX_EXTRA_SUBSTITUTERS }}")))
      | length) == 2
    and ([
      .jobs."build-linux-eval".steps[],
      .jobs."build-linux-matrix".steps[]
    ] | map(select(.uses
      == "nixbuild/nix-quick-install-action@9f63be77f412a248c9d9a65a4c82cf066cdf8f0c"))
      | map(select(.with.nix_conf | contains("${{ env.NIX_EXTRA_TRUSTED_PUBLIC_KEYS }}")))
      | length) == 2
    and ([
      .jobs[].steps[]?
    ] | map(select(
      .uses == "Mic92/hestia@b21a1aaf8c3d5c2e430c9ba278c0f78abd46a320"
      and .with.version == "${{ env.HESTIA_VERSION }}"
      and .with."upstream-cache-filter" == true
      and .with."upstream-cache-key-names"
        == "${{ env.HESTIA_UPSTREAM_CACHE_KEY_NAMES }}"
    )) | length) == 3
    and (.jobs."build-linux".needs | join(","))
      == "build-linux-eval,build-linux-matrix"
    and .jobs."build-linux".if == "always()"
  ' "$CI_WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "Linux aggregate result rejects missing or failed matrix states" {
  local script
  script=$(ci_step_script "build-linux" "Verify Linux matrix result")

  run env EVAL_RESULT=success ANY_JOBS=true MATRIX_RESULT=success bash -c "$script"
  [ "$status" -eq 0 ]

  run env EVAL_RESULT=success ANY_JOBS=false MATRIX_RESULT=skipped bash -c "$script"
  [ "$status" -eq 0 ]

  run env EVAL_RESULT=failure ANY_JOBS=false MATRIX_RESULT=skipped bash -c "$script"
  [ "$status" -ne 0 ]

  run env EVAL_RESULT=success ANY_JOBS=true MATRIX_RESULT=failure bash -c "$script"
  [ "$status" -ne 0 ]

  run env EVAL_RESULT=success ANY_JOBS= MATRIX_RESULT=skipped bash -c "$script"
  [ "$status" -ne 0 ]
}

@test "private and production smoke steps run in the required order" {
  run yq -e '
    ([.jobs.smoke.steps[] | select(
      .name == "Build private smoke executable"
      or .name == "Check live upstream contracts"
      or .name == "Create disposable updater checkout"
      or .name == "Exercise production difit updater"
      or .name == "Verify repository remained unchanged"
    )] | length) == 5
    and ([.jobs.smoke.steps[] | select(
      .name == "Build private smoke executable"
    )] | length) == 1
    and ([.jobs.smoke.steps[] | select(
      .name == "Check live upstream contracts"
    )] | length) == 1
    and ([.jobs.smoke.steps[] | select(
      .name == "Create disposable updater checkout"
    )] | length) == 1
    and ([.jobs.smoke.steps[] | select(
      .name == "Exercise production difit updater"
    )] | length) == 1
    and ([.jobs.smoke.steps[] | select(
      .name == "Verify repository remained unchanged"
    )] | length) == 1
  ' "$WORKFLOW"
  [ "$status" -eq 0 ]

  run yq -e '
    (.jobs.smoke.steps | length) as $count
    | (.jobs.smoke.steps | to_entries | map(select(
      .value.name == "Build private smoke executable"
    ))[0].key) as $build
    | (.jobs.smoke.steps | to_entries | map(select(
      .value.name == "Check live upstream contracts"
    ))[0].key) as $private
    | (.jobs.smoke.steps | to_entries | map(select(
      .value.name == "Create disposable updater checkout"
    ))[0].key) as $clone
    | (.jobs.smoke.steps | to_entries | map(select(
      .value.name == "Exercise production difit updater"
    ))[0].key) as $production
    | (.jobs.smoke.steps | to_entries | map(select(
      .value.name == "Verify repository remained unchanged"
    ))[0].key) as $final
    | [
        ($build < $private),
        ($private < $clone),
        ($clone < $production),
        ($production < $final),
        ($final == ($count - 1))
      ]
      | all
  ' "$WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "private metadata smoke remains enabled" {
  local build_script
  local private_script
  build_script=$(step_script "Build private smoke executable")
  private_script=$(step_script "Check live upstream contracts")

  [[ "$build_script" == *".#checks.x86_64-linux.update-pins-smoke"* ]]
  [[ "$build_script" == *'--no-link'* ]]
  [[ "$build_script" == *'--no-write-lock-file'* ]]
  [[ "$private_script" == *'"$UPDATE_PINS_SMOKE"'* ]]
  [ "$(yq -r '.jobs.smoke.steps[] | select(.name == "Check live upstream contracts") | .env.UPDATE_PINS_SMOKE' "$WORKFLOW")" = '${{ steps.build.outputs.path }}/bin/update-pins-smoke' ]
}

@test "production updater runs in a bounded disposable checkout" {
  local clone_script
  local production_script
  clone_script=$(step_script "Create disposable updater checkout" | normalize_lines)
  production_script=$(
    step_script "Exercise production difit updater" | normalize_lines
  )

  grep -Fxq 'test ! -e "$UPDATE_PINS_CHECKOUT"' <<<"$clone_script"
  grep -Fxq \
    'git clone --no-local --no-checkout --single-branch --depth=1 --no-tags "$GITHUB_WORKSPACE" "$UPDATE_PINS_CHECKOUT"' \
    <<<"$clone_script"
  grep -Fxq \
    'git -C "$UPDATE_PINS_CHECKOUT" checkout --quiet --detach "$GITHUB_SHA"' \
    <<<"$clone_script"
  grep -Fxq \
    'test "$(git -C "$UPDATE_PINS_CHECKOUT" rev-parse HEAD)" = "$GITHUB_SHA"' \
    <<<"$clone_script"
  grep -Fxq \
    'git -C "$UPDATE_PINS_CHECKOUT" remote remove origin' \
    <<<"$clone_script"
  grep -Fxq \
    'clone_status="$(git -C "$UPDATE_PINS_CHECKOUT" status --short)"' \
    <<<"$clone_script"
  grep -Fxq 'test -z "$clone_status"' <<<"$clone_script"
  run yq -e '
    [.jobs.smoke.steps[] | select(
      .name == "Exercise production difit updater"
    )][0].working-directory == "${{ runner.temp }}/update-pins-check"
  ' "$WORKFLOW"
  [ "$status" -eq 0 ]
  grep -Fxq \
    'timeout 15m nix run .#update-pins -- --force --check difit' \
    <<<"$production_script"
  grep -Fxq 'git diff --exit-code' <<<"$production_script"
  grep -Fxq 'clone_status="$(git status --short)"' <<<"$production_script"
  grep -Fxq 'test -z "$clone_status"' <<<"$production_script"

  local all_scripts
  all_scripts=$(
    yq -r '[.jobs.smoke.steps[].run // ""] | join("\n")' "$WORKFLOW" |
      normalize_lines
  )
  [ "$(grep -Fc 'nix run .#update-pins' <<<"$all_scripts")" -eq 1 ]
}

@test "original checkout is checked even after a smoke failure" {
  run yq -e '
    ([.jobs.smoke.steps[] | select(
      .name == "Verify repository remained unchanged"
    )][0].if) == "always()"
  ' "$WORKFLOW"
  [ "$status" -eq 0 ]

  local final_script
  final_script=$(
    step_script "Verify repository remained unchanged" | normalize_lines
  )
  grep -Fxq \
    'git -C "$GITHUB_WORKSPACE" diff --exit-code' \
    <<<"$final_script"
  grep -Fxq \
    'original_status="$(git -C "$GITHUB_WORKSPACE" status --short)"' \
    <<<"$final_script"
  grep -Fxq 'test -z "$original_status"' <<<"$final_script"
}

@test "smoke workflow cannot publish or duplicate dependency installation" {
  local script
  script=$(yq -r '[.jobs.smoke.steps[].run // ""] | join("\n")' "$WORKFLOW")

  ! grep -Eq '(^|[[:space:];|&])(npm|pnpm)([[:space:]]|$)' \
    <<<"$script"
  ! grep -Eq \
    '(^|[[:space:];|&])git[[:space:]].*(add|commit|push)([[:space:]]|$)' \
    <<<"$script"
}
