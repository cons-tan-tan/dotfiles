#!/usr/bin/env bats

DOTFILES_TEST_REPO_ROOT=${DOTFILES_TEST_REPO_ROOT:-$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)}
source "$DOTFILES_TEST_REPO_ROOT/modules/features/checks/_interface/bats/test-helper.bash"

setup() {
  REPO_ROOT="$DOTFILES_TEST_REPO_ROOT"
  WORKFLOW_DIR="$REPO_ROOT/.github/workflows"
  WORKFLOW="$WORKFLOW_DIR/update-pins-smoke.yaml"
  CI_WORKFLOW="$WORKFLOW_DIR/ci.yaml"
  HESTIA_WORKFLOW="$WORKFLOW_DIR/hestia-system.yaml"
  CACHE_GC_WORKFLOW="$WORKFLOW_DIR/cache-gc.yaml"
  CACHE_SETTINGS="$REPO_ROOT/modules/features/platform/nix-settings/_data/cache.nix"
  CI_SCRIPT_DIR="$REPO_ROOT/modules/features/ci/_scripts"
  HESTIA_MATRIX_VALIDATOR="$CI_SCRIPT_DIR/validate_hestia_matrix.py"
  HESTIA_BUILD_SCRIPT="$CI_SCRIPT_DIR/prefetch_hestia_closure_and_build.sh"
  SUBSTITUTER_CHECK_SCRIPT="$CI_SCRIPT_DIR/verify_binary_substituters.sh"
}

workflow_files() {
  local directory=$1
  local -a files
  shopt -s nullglob
  files=("$directory"/*.yml "$directory"/*.yaml)
  shopt -u nullglob
  ((${#files[@]} > 0)) || return 1
  printf '%s\n' "${files[@]}" | sort
}

check_universal_workflow_policy() {
  local directory=$1
  local visited_file=${2:-}
  local workflow
  local checkout_count=0
  local -a workflows
  mapfile -t workflows < <(workflow_files "$directory")
  ((${#workflows[@]} > 0)) || return 1

  for workflow in "${workflows[@]}"; do
    yq -e '
      .permissions.contents == "read"
      and (.permissions | length) == 1
      and ((.jobs | kind) == "map")
      and ((.jobs | length) > 0)
      and ([.jobs[] | select(has("uses") | not) | has("timeout-minutes")] | all)
      and ([.jobs[] | select(has("uses")) | has("timeout-minutes") | not] | all)
      and ([.jobs[] | select(has("timeout-minutes")) | .["timeout-minutes"] |
        (tag == "!!int" and . > 0)] | all)
      and ([.jobs[] | .steps[]? |
        (has("name") and (.name | tag == "!!str" and length > 0))] | all)
      and ([.. | select(kind == "map") | .uses // "" | select(length > 0)
        | select(test("^\\./") | not)
        | test("@[0-9a-f]{40}$")] | all)
      and ([.jobs[] | .uses // "" | select(test("^\\./"))
        | test("^\\./\\.github/workflows/[a-z0-9-]+\\.yaml$")] | all)
      and ([.. | select(kind == "map") | select(
        (.uses // "") | test("^actions/checkout@")
      ) | .with."persist-credentials" == false] | all)
    ' "$workflow" >/dev/null || return 1
    checkout_count=$((checkout_count + $(yq -r '[.. | select(kind == "map") | select(
      (.uses // "") | test("^actions/checkout@")
    )] | length' "$workflow")))
    if [[ -n "$visited_file" ]]; then
      basename "$workflow" >>"$visited_file"
    fi
  done

  ((checkout_count > 0))
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

hestia_step_script() {
  local job=$1
  local name=$2
  yq -r ".jobs.\"$job\".steps[] | select(.name == \"$name\") | .run" "$HESTIA_WORKFLOW"
}

run_hestia_matrix_validation() {
  local matrix=$1
  local manifest_version=$2
  local system=${3:-x86_64-linux}
  local any_jobs=${4:-}
  local matrix_output_max_chars=${5:-499000}
  MATRIX_OUTPUT="$BATS_TEST_TMPDIR/matrix-output"
  : >"$MATRIX_OUTPUT"

  if [[ -z "$any_jobs" ]]; then
    any_jobs=$(jq -r '.include | length > 0' <<<"$matrix" 2>/dev/null) || any_jobs=invalid
  fi

  run env \
    GITHUB_OUTPUT="$MATRIX_OUTPUT" \
    HESTIA_ANY_JOBS="$any_jobs" \
    HESTIA_MANIFEST_VERSION="$manifest_version" \
    HESTIA_MATRIX="$matrix" \
    MATRIX_OUTPUT_MAX_CHARS="$matrix_output_max_chars" \
    SYSTEM="$system" \
    python3 "$HESTIA_MATRIX_VALIDATOR"
}

run_ci_build_step() {
  local curl_status=$1
  local import_outcomes=$2
  local realise_status=$3
  local build_status=$4
  local missing_paths=${5:-/nix/store/11111111111111111111111111111111-upstream-reference}
  local stub_dir="$BATS_TEST_TMPDIR/ci-build-stubs"
  local calls="$BATS_TEST_TMPDIR/ci-build-calls"
  local import_count="$BATS_TEST_TMPDIR/ci-build-import-count"
  local installable=/nix/store/00000000000000000000000000000000-test.drv^\*

  mkdir -p "$stub_dir"
  write_bash_stub "$stub_dir/curl" <<'SH'
printf 'curl\n' >>"$CI_BUILD_CALLS"
printf 'closure'
exit "$CI_CURL_STATUS"
SH
  write_bash_stub "$stub_dir/nix-store" <<'SH'
case "${1:-}" in
  --import)
    cat >/dev/null
    count=0
    if [[ -f "$CI_BUILD_IMPORT_COUNT" ]]; then
      read -r count <"$CI_BUILD_IMPORT_COUNT"
    fi
    IFS=, read -r -a outcomes <<<"$CI_IMPORT_OUTCOMES"
    IFS=, read -r -a missing_paths <<<"$CI_MISSING_PATHS"
    outcome=${outcomes[$count]:-error}
    missing_path=${missing_paths[$count]:-${missing_paths[0]}}
    printf '%s\n' "$((count + 1))" >"$CI_BUILD_IMPORT_COUNT"
    printf 'nix-store <import>\n' >>"$CI_BUILD_CALLS"
    case "$outcome" in
      success) exit 0 ;;
      missing)
        printf "error: path '%s' is not valid\n" "$missing_path" >&2
        exit 1
        ;;
      *)
        printf 'error: invalid closure archive\n' >&2
        exit 1
        ;;
    esac
    ;;
  --realise)
    printf 'nix-store <realise> <%s>\n' "$2" >>"$CI_BUILD_CALLS"
    exit "$CI_REALISE_STATUS"
    ;;
  *) exit 2 ;;
esac
SH
  write_bash_stub "$stub_dir/nix" <<'SH'
printf 'nix' >>"$CI_BUILD_CALLS"
printf ' <%s>' "$@" >>"$CI_BUILD_CALLS"
printf '\n' >>"$CI_BUILD_CALLS"
exit "$CI_BUILD_STATUS"
SH

  run env \
    PATH="$stub_dir:$PATH" \
    CI_BUILD_CALLS="$calls" \
    CI_BUILD_IMPORT_COUNT="$import_count" \
    CI_BUILD_STATUS="$build_status" \
    CI_CURL_STATUS="$curl_status" \
    CI_IMPORT_OUTCOMES="$import_outcomes" \
    CI_MISSING_PATHS="$missing_paths" \
    CI_REALISE_STATUS="$realise_status" \
    HESTIA_LISTEN=127.0.0.1:37515 \
    INSTALLABLES="$installable" \
    bash "$HESTIA_BUILD_SCRIPT"
}

run_substituter_check() {
  local configured_substituters=$1
  local stub_dir="$BATS_TEST_TMPDIR/substituter-check-stubs"

  mkdir -p "$stub_dir"
  write_bash_stub "$stub_dir/nix" <<'SH'
if [[ "$*" != "config show substituters" ]]; then
  exit 2
fi
printf '%s\n' "$CONFIGURED_SUBSTITUTERS"
SH

  run env \
    PATH="$stub_dir:$PATH" \
    CONFIGURED_SUBSTITUTERS="$configured_substituters" \
    NIX_EXTRA_SUBSTITUTERS="https://cache.numtide.com https://nix-community.cachix.org" \
    bash "$SUBSTITUTER_CHECK_SCRIPT"
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

@test "upstream smoke workflow reuses pinned CI lane actions" {
  local -a actions
  local action
  mapfile -t actions < <(
    yq -r '.jobs.smoke.steps[].uses // "" | select(length > 0)' "$WORKFLOW"
  )
  [ "${#actions[@]}" -eq 3 ]
  for action in "${actions[@]}"; do
    [[ "$action" =~ ^[^@]+@[0-9a-f]{40}$ ]] || return 1
    grep -Fq "uses: $action" "$CI_WORKFLOW" \
      || grep -Fq "uses: $action" "$HESTIA_WORKFLOW" \
      || return 1
  done
}

@test "all discovered workflows follow the universal policy" {
  check_universal_workflow_policy "$WORKFLOW_DIR"
}

@test "universal policy includes a fourth discovered workflow" {
  local fixture_dir="$BATS_TEST_TMPDIR/workflows"
  local visited="$BATS_TEST_TMPDIR/visited"
  local name
  mkdir -p "$fixture_dir"

  for name in first second third fourth; do
    cat >"$fixture_dir/$name.yaml" <<'YAML'
on: push
permissions:
  contents: read
jobs:
  check:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - name: Check out repository
        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1
        with:
          persist-credentials: false
YAML
  done

  check_universal_workflow_policy "$fixture_dir" "$visited"
  [ "$(wc -l <"$visited")" -eq 4 ]
  grep -Fxq fourth.yaml "$visited"
}

@test "universal policy rejects missing jobs and non-positive finite timeouts" {
  local fixture_dir="$BATS_TEST_TMPDIR/invalid-workflows"
  local invalid
  mkdir -p "$fixture_dir"

  cat >"$fixture_dir/baseline.yaml" <<'YAML'
on: push
permissions:
  contents: read
jobs:
  check:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - name: Check out repository
        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1
        with:
          persist-credentials: false
YAML

  for invalid in no-jobs missing zero fractional string; do
    case "$invalid" in
    no-jobs)
      cat >"$fixture_dir/invalid.yaml" <<'YAML'
on: push
permissions:
  contents: read
jobs: {}
YAML
      ;;
    missing)
      timeout_line=
      ;;
    zero)
      timeout_line='    timeout-minutes: 0'
      ;;
    fractional)
      timeout_line='    timeout-minutes: 1.5'
      ;;
    string)
      timeout_line='    timeout-minutes: "10"'
      ;;
    esac
    if [ "$invalid" != no-jobs ]; then
      cat >"$fixture_dir/invalid.yaml" <<YAML
on: push
permissions:
  contents: read
jobs:
  check:
    runs-on: ubuntu-latest
$timeout_line
    steps:
      - name: Check out repository
        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1
        with:
          persist-credentials: false
YAML
    fi

    run check_universal_workflow_policy "$fixture_dir"
    [ "$status" -ne 0 ]
  done
}

@test "universal policy rejects unnamed steps" {
  local fixture_dir="$BATS_TEST_TMPDIR/unnamed-step-workflow"
  mkdir -p "$fixture_dir"

  cat >"$fixture_dir/unnamed.yaml" <<'YAML'
on: push
permissions:
  contents: read
jobs:
  check:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1
        with:
          persist-credentials: false
YAML

  run check_universal_workflow_policy "$fixture_dir"
  [ "$status" -ne 0 ]
}

@test "cache GC does not check out the repository" {
  run yq -e '
    ([.. | select(kind == "map") | select(
      (.uses // "") | test("^actions/checkout@")
    )] | length) == 0
  ' "$CACHE_GC_WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "flake checks are the only source of repository gates" {
  run yq -e '
    ([.. | select(kind == "map") | .run // ""] | map(select(length > 0))) as $runs
    | ([.. | select(kind == "map") | .uses // ""] | map(select(length > 0))) as $uses
    | [
        (.jobs.fmt == null),
        (.jobs.reuse == null),
        (([$runs[] | select(
          contains("nix flake check --no-build --all-systems")
        )] | length) == 1),
        (([$runs[] | select(
          contains("nix flake check --no-build --all-systems")
        )][0]) == "nix flake check --no-build --all-systems"),
        (([$runs[] | select(contains("nix run .#fmt"))] | length) == 0),
        (([$runs[] | select(contains("reuse lint"))] | length) == 0),
        (([$uses[] | select(test("^fsfe/reuse-action@"))] | length) == 0)
      ]
      | all
  ' "$CI_WORKFLOW"
  [ "$status" -eq 0 ]
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
  version=$(yq -r '.env.HESTIA_VERSION' "$HESTIA_WORKFLOW")
  upstream_key_names=$(yq -r '.env.HESTIA_UPSTREAM_CACHE_KEY_NAMES' "$HESTIA_WORKFLOW")

  [ "$(yq -r '.jobs.smoke.steps[] | select(.uses == "Mic92/hestia@b21a1aaf8c3d5c2e430c9ba278c0f78abd46a320") | .with.version' "$WORKFLOW")" = "$version" ]
  [ "$(yq -r '.jobs.smoke.steps[] | select(.uses == "Mic92/hestia@b21a1aaf8c3d5c2e430c9ba278c0f78abd46a320") | .with."upstream-cache-filter"' "$WORKFLOW")" = true ]
  [ "$(yq -r '.jobs.smoke.steps[] | select(.uses == "Mic92/hestia@b21a1aaf8c3d5c2e430c9ba278c0f78abd46a320") | .with."upstream-cache-key-names"' "$WORKFLOW")" = "$upstream_key_names" ]
  [ "$(yq -r '.jobs.gc.steps[] | select(.uses == "Mic92/hestia@b21a1aaf8c3d5c2e430c9ba278c0f78abd46a320") | .with.version' "$CACHE_GC_WORKFLOW")" = "$version" ]
}

@test "flake evaluation and system lanes start independently" {
  run yq -e '
    .jobs."flake-eval".name == "evaluate / flake"
    and .jobs."flake-eval".runs-on == "ubuntu-latest"
    and .jobs."flake-eval".needs == null
    and .jobs.linux.name == "linux"
    and .jobs.linux.uses == "./.github/workflows/hestia-system.yaml"
    and .jobs.linux.with.system == "x86_64-linux"
    and .jobs.linux.needs == null
    and .jobs.darwin.name == "darwin"
    and .jobs.darwin.uses == "./.github/workflows/hestia-system.yaml"
    and .jobs.darwin.with.system == "aarch64-darwin"
    and .jobs.darwin.needs == null
  ' "$CI_WORKFLOW"
  [ "$status" -eq 0 ]

  run yq -e '
    .on.workflow_call.inputs.system.required == true
    and .on.workflow_call.inputs.system.type == "string"
    and .jobs.evaluate.name == "evaluate"
    and .jobs.evaluate.runs-on == "ubuntu-latest"
    and .jobs.evaluate.needs == null
    and .jobs.evaluate.outputs.matrix
      == "${{ steps.matrix.outputs.matrix }}"
    and .jobs.evaluate.outputs."any-jobs"
      == "${{ steps.matrix.outputs.any-jobs }}"
    and .jobs.evaluate.outputs."manifest-version"
      == "${{ steps.matrix.outputs.manifest-version }}"
    and ([.jobs.evaluate.steps[] | select(
      .uses == "Mic92/hestia@b21a1aaf8c3d5c2e430c9ba278c0f78abd46a320"
    )] | length) == 1
    and ([.jobs.evaluate.steps[] | select(
      .uses == "Mic92/hestia/matrix@b21a1aaf8c3d5c2e430c9ba278c0f78abd46a320"
    )] | length) == 1
    and ([.jobs.evaluate.steps[] | select(
      .uses == "Mic92/hestia/matrix@b21a1aaf8c3d5c2e430c9ba278c0f78abd46a320"
    )][0].id) == "hestia-matrix"
    and ([.jobs.evaluate.steps[] | select(
      .uses == "Mic92/hestia/matrix@b21a1aaf8c3d5c2e430c9ba278c0f78abd46a320"
    )][0].with.flake) == ".#hydraJobs.ci.${{ inputs.system }}"
    and ([.jobs.evaluate.steps[] | select(
      .uses == "Mic92/hestia/matrix@b21a1aaf8c3d5c2e430c9ba278c0f78abd46a320"
    )][0].with."attr-prefix") == "hydraJobs.ci.${{ inputs.system }}"
    and ([.jobs.evaluate.steps[] | select(
      .uses == "Mic92/hestia/matrix@b21a1aaf8c3d5c2e430c9ba278c0f78abd46a320"
    )][0].with."nix-eval-jobs"
      == "nix run nixpkgs#nix-eval-jobs --inputs-from . -- --workers 1 --max-memory-size 12288")
    and ([.jobs.evaluate.steps[] | select(.id == "matrix")]
      | length) == 1
    and ([.jobs.evaluate.steps[] | select(.id == "matrix")][0].name)
      == "Validate system matrix"
    and ([.jobs.evaluate.steps[] | select(.id == "matrix")][0].shell)
      == "bash"
    and ([.jobs.evaluate.steps[] | select(.id == "matrix")][0].run)
      == "python3 modules/features/ci/_scripts/validate_hestia_matrix.py"
  ' "$HESTIA_WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "system matrix validation preserves nonempty and empty matrices" {
  local empty='{"include":[]}'
  local linux='{"include":[{"drvPath":"/nix/store/linux-a.drv","system":"x86_64-linux","name":"linux-a","os":["ubuntu-latest"],"installables":"/nix/store/linux-a.drv^*"}]}'
  local linux_with_axis='{"include":[{"drvPath":"/nix/store/linux-a.drv","system":"x86_64-linux","name":"linux-a","os":["ubuntu-latest"],"installables":"/nix/store/linux-a.drv^*"}],"unexpected":["axis"]}'

  run_hestia_matrix_validation "$linux_with_axis" 12
  [ "$status" -eq 0 ]
  [ "$(sed -n 's/^any-jobs=//p' "$MATRIX_OUTPUT")" = true ]
  [ "$(sed -n 's/^manifest-version=//p' "$MATRIX_OUTPUT")" -eq 12 ]
  [ "$(sed -n 's/^matrix=//p' "$MATRIX_OUTPUT")" = "$linux" ]

  run_hestia_matrix_validation "$empty" 0
  [ "$status" -eq 0 ]
  [ "$(sed -n 's/^any-jobs=//p' "$MATRIX_OUTPUT")" = false ]
  [ "$(sed -n 's/^matrix=//p' "$MATRIX_OUTPUT")" = "$empty" ]
}

@test "system matrix validation requires a matching manifest registration" {
  local linux='{"include":[{"drvPath":"/nix/store/linux-a.drv","system":"x86_64-linux","name":"linux-a","os":["ubuntu-latest"],"installables":"/nix/store/linux-a.drv^*"}]}'

  run_hestia_matrix_validation "$linux" 0
  [ "$status" -ne 0 ]

  run_hestia_matrix_validation "$linux" 12 x86_64-linux false
  [ "$status" -ne 0 ]
}

@test "system matrix validation rejects malformed, mixed, and oversized inputs" {
  local empty='{"include":[]}'
  local linux='{"include":[{"drvPath":"/nix/store/linux-a.drv","system":"x86_64-linux","name":"linux-a","os":["ubuntu-latest"],"installables":"/nix/store/linux-a.drv^*"}]}'
  local incomplete='{"include":[{"drvPath":"/nix/store/linux-a.drv","system":"x86_64-linux"}]}'
  local invalid_os='{"include":[{"drvPath":"/nix/store/linux-a.drv","system":"x86_64-linux","name":"linux-a","os":"ubuntu-latest","installables":"/nix/store/linux-a.drv^*"}]}'
  local mixed='{"include":[{"drvPath":"/nix/store/darwin-a.drv","system":"aarch64-darwin","name":"darwin-a","os":["macos-15"],"installables":"/nix/store/darwin-a.drv^*"}]}'
  local duplicate='{"include":[{"drvPath":"/nix/store/shared.drv","system":"x86_64-linux","name":"first","os":["ubuntu-latest"],"installables":"/nix/store/shared.drv^*"},{"drvPath":"/nix/store/shared.drv","system":"x86_64-linux","name":"second","os":["ubuntu-latest"],"installables":"/nix/store/shared.drv^*"}]}'
  local oversized

  run_hestia_matrix_validation '{' 1
  [ "$status" -ne 0 ]

  run_hestia_matrix_validation '{}' 1
  [ "$status" -ne 0 ]

  run_hestia_matrix_validation "$incomplete" 1
  [ "$status" -ne 0 ]

  run_hestia_matrix_validation "$invalid_os" 1
  [ "$status" -ne 0 ]

  run_hestia_matrix_validation "$duplicate" 1
  [ "$status" -ne 0 ]

  run_hestia_matrix_validation "$mixed" 1
  [ "$status" -ne 0 ]

  oversized=$(jq -cn '{include: [range(257) | {drvPath: ("/nix/store/" + tostring + ".drv"), system: "x86_64-linux", name: ("row-" + tostring), os: ["ubuntu-latest"], installables: ("/nix/store/" + tostring + ".drv^*")}]}')
  run_hestia_matrix_validation "$oversized" 1
  [ "$status" -ne 0 ]

  run_hestia_matrix_validation "$empty" latest
  [ "$status" -ne 0 ]

  run_hestia_matrix_validation "$linux" 18446744073709551615
  [ "$status" -eq 0 ]
  [ "$(sed -n 's/^manifest-version=//p' "$MATRIX_OUTPUT")" = 18446744073709551615 ]

  run_hestia_matrix_validation "$linux" 18446744073709551616
  [ "$status" -ne 0 ]

  run_hestia_matrix_validation "$linux" 1 x86_64-linux true 20
  [ "$status" -ne 0 ]
}

@test "system lane waits for and builds its evaluated derivations" {
  run yq -e '
    .jobs.build.needs == "evaluate"
    and .jobs.build."timeout-minutes" == 90
    and .jobs.build.if
      == "needs.evaluate.result == '\''success'\'' && needs.evaluate.outputs.any-jobs == '\''true'\''"
    and .jobs.build."runs-on" == "${{ matrix.os }}"
    and .jobs.build.strategy."fail-fast" == false
    and .jobs.build.strategy."max-parallel" == null
    and .jobs.build.strategy.matrix
      == "${{ fromJSON(needs.evaluate.outputs.matrix) }}"
    and ([.jobs.build.steps[] | select(
      .uses == "Mic92/hestia@b21a1aaf8c3d5c2e430c9ba278c0f78abd46a320"
    )][0].with."wait-manifest-version")
      == "${{ needs.evaluate.outputs.manifest-version }}"
    and ([.jobs.build.steps[] | select(
      .name == "Prefetch derivation closure and build"
    )][0].env.INSTALLABLES) == "${{ matrix.installables }}"
    and ([.jobs.build.steps[] | select(
      .name == "Prefetch derivation closure and build"
    )][0].run)
      == "bash modules/features/ci/_scripts/prefetch_hestia_closure_and_build.sh"
    and ([.jobs.build.steps[] | select(
      .name == "Verify binary substituters"
    )][0].run)
      == "bash modules/features/ci/_scripts/verify_binary_substituters.sh"
    and ([.jobs.build.steps[] | select(
      .name == "Check out CI scripts"
    )][0].with."persist-credentials" == false)
    and ([.jobs.build.steps[] | select(
      .name == "Check out CI scripts"
    )][0].with."sparse-checkout") == "modules/features/ci/_scripts"
  ' "$HESTIA_WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "Hestia CI scripts pass static checks" {
  run shellcheck "$HESTIA_BUILD_SCRIPT" "$SUBSTITUTER_CHECK_SCRIPT"
  [ "$status" -eq 0 ]

  run env \
    PYTHONPYCACHEPREFIX="$BATS_TEST_TMPDIR/pycache" \
    python3 -m py_compile "$HESTIA_MATRIX_VALIDATOR"
  [ "$status" -eq 0 ]
}

@test "system lane requires all binary substituters" {
  run_substituter_check \
    "https://cache.nixos.org https://cache.numtide.com https://nix-community.cachix.org http://127.0.0.1:37515"
  [ "$status" -eq 0 ]

  run_substituter_check \
    "https://cache.nixos.org https://cache.numtide.com https://nix-community.cachix.org"
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing substituter: http://127.0.0.1:"* ]]
}

@test "matrix build resolves a filtered reference and retries closure import" {
  run_ci_build_step 0 missing,success 0 0

  [ "$status" -eq 0 ]
  [[ "$output" == *"Substituting filtered Hestia closure reference"* ]]
  [[ "$output" != *"::warning::"* ]]
  [ "$(cat "$BATS_TEST_TMPDIR/ci-build-calls")" = $'curl\nnix-store <import>\nnix-store <realise> </nix/store/11111111111111111111111111111111-upstream-reference>\ncurl\nnix-store <import>\nnix <build> </nix/store/00000000000000000000000000000000-test.drv^*>' ]
}

@test "matrix build falls back after an unrecognized closure import failure" {
  run_ci_build_step 0 error 0 0

  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning::Hestia closure prefetch failed"* ]]
  [ "$(cat "$BATS_TEST_TMPDIR/ci-build-calls")" = $'curl\nnix-store <import>\nnix <build> </nix/store/00000000000000000000000000000000-test.drv^*>' ]
}

@test "matrix build falls back after closure download failure" {
  run_ci_build_step 22 success 0 0

  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning::Hestia closure prefetch failed"* ]]
  [ "$(cat "$BATS_TEST_TMPDIR/ci-build-calls")" = $'curl\nnix-store <import>\nnix <build> </nix/store/00000000000000000000000000000000-test.drv^*>' ]
}

@test "matrix build does not realise an invalid reported store path" {
  run_ci_build_step 0 missing 0 0 /nix/store/not-a-valid-store-path

  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning::Hestia closure prefetch failed"* ]]
  [ "$(cat "$BATS_TEST_TMPDIR/ci-build-calls")" = $'curl\nnix-store <import>\nnix <build> </nix/store/00000000000000000000000000000000-test.drv^*>' ]
}

@test "matrix build does not realise a derivation reported as missing" {
  run_ci_build_step 0 missing 0 0 /nix/store/22222222222222222222222222222222-input.drv

  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning::Hestia closure prefetch failed"* ]]
  [ "$(cat "$BATS_TEST_TMPDIR/ci-build-calls")" = $'curl\nnix-store <import>\nnix <build> </nix/store/00000000000000000000000000000000-test.drv^*>' ]
}

@test "matrix build falls back when filtered reference substitution fails" {
  run_ci_build_step 0 missing 1 0

  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning::Hestia closure prefetch failed"* ]]
  [ "$(cat "$BATS_TEST_TMPDIR/ci-build-calls")" = $'curl\nnix-store <import>\nnix-store <realise> </nix/store/11111111111111111111111111111111-upstream-reference>\nnix <build> </nix/store/00000000000000000000000000000000-test.drv^*>' ]
}

@test "matrix build stops retrying a repeated missing reference" {
  run_ci_build_step 0 missing,missing 0 0

  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning::Hestia closure prefetch failed"* ]]
  [ "$(cat "$BATS_TEST_TMPDIR/ci-build-calls")" = $'curl\nnix-store <import>\nnix-store <realise> </nix/store/11111111111111111111111111111111-upstream-reference>\ncurl\nnix-store <import>\nnix <build> </nix/store/00000000000000000000000000000000-test.drv^*>' ]
}

@test "matrix build resolves at most four distinct missing references" {
  local calls="$BATS_TEST_TMPDIR/ci-build-calls"
  local missing_paths
  missing_paths=/nix/store/11111111111111111111111111111111-ref-one
  missing_paths+=,/nix/store/22222222222222222222222222222222-ref-two
  missing_paths+=,/nix/store/33333333333333333333333333333333-ref-three
  missing_paths+=,/nix/store/44444444444444444444444444444444-ref-four
  missing_paths+=,/nix/store/55555555555555555555555555555555-ref-five

  run_ci_build_step 0 missing,missing,missing,missing,missing 0 0 "$missing_paths"

  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning::Hestia closure prefetch failed"* ]]
  [ "$(grep -c '^curl$' "$calls")" -eq 5 ]
  [ "$(grep -c '^nix-store <import>$' "$calls")" -eq 5 ]
  [ "$(grep -c '^nix-store <realise>' "$calls")" -eq 4 ]
  ! grep -Fq '/nix/store/55555555555555555555555555555555-ref-five' "$calls"
  [ "$(tail -n 1 "$calls")" = 'nix <build> </nix/store/00000000000000000000000000000000-test.drv^*>' ]
}

@test "matrix build failure remains fatal after successful prefetch" {
  run_ci_build_step 0 success 0 42

  [ "$status" -eq 42 ]
  [[ "$output" != *"::warning::"* ]]
  [ "$(cat "$BATS_TEST_TMPDIR/ci-build-calls")" = $'curl\nnix-store <import>\nnix <build> </nix/store/00000000000000000000000000000000-test.drv^*>' ]
}

@test "system lane keeps public substituters and a stable result" {
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
    ' "$HESTIA_WORKFLOW"
  [ "$status" -eq 0 ]

  run yq -e '
    ([
      .jobs.evaluate.steps[],
      .jobs.build.steps[]
    ] | map(select(.uses
      == "nixbuild/nix-quick-install-action@9f63be77f412a248c9d9a65a4c82cf066cdf8f0c"))
      | length) == 2
    and ([
      .jobs.evaluate.steps[],
      .jobs.build.steps[]
    ] | map(select(.uses
      == "nixbuild/nix-quick-install-action@9f63be77f412a248c9d9a65a4c82cf066cdf8f0c"))
      | map(select(.with.nix_conf | contains("${{ env.NIX_EXTRA_SUBSTITUTERS }}")))
      | length) == 2
    and ([
      .jobs.evaluate.steps[],
      .jobs.build.steps[]
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
    )) | length) == 2
    and (.jobs.result.needs | join(",")) == "evaluate,build"
    and .jobs.result.if == "always()"
  ' "$HESTIA_WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "system result rejects missing or failed matrix states" {
  local script
  script=$(hestia_step_script "result" "Verify system result")

  run env EVAL_RESULT=success ANY_JOBS=true BUILD_RESULT=success bash -c "$script"
  [ "$status" -eq 0 ]

  run env EVAL_RESULT=success ANY_JOBS=false BUILD_RESULT=skipped bash -c "$script"
  [ "$status" -eq 0 ]

  run env EVAL_RESULT=failure ANY_JOBS=false BUILD_RESULT=skipped bash -c "$script"
  [ "$status" -ne 0 ]

  run env EVAL_RESULT=success ANY_JOBS=true BUILD_RESULT=failure bash -c "$script"
  [ "$status" -ne 0 ]

  run env EVAL_RESULT=success ANY_JOBS= BUILD_RESULT=skipped bash -c "$script"
  [ "$status" -ne 0 ]
}

@test "required result accepts only successful independent lanes" {
  local script
  script=$(ci_step_script "required" "Verify required results")

  run env FLAKE_EVAL_RESULT=success LINUX_RESULT=success DARWIN_RESULT=success bash -c "$script"
  [ "$status" -eq 0 ]

  run env FLAKE_EVAL_RESULT=failure LINUX_RESULT=success DARWIN_RESULT=success bash -c "$script"
  [ "$status" -ne 0 ]

  run env FLAKE_EVAL_RESULT=success LINUX_RESULT=failure DARWIN_RESULT=success bash -c "$script"
  [ "$status" -ne 0 ]

  run env FLAKE_EVAL_RESULT=success LINUX_RESULT=success DARWIN_RESULT=cancelled bash -c "$script"
  [ "$status" -ne 0 ]

  run yq -e '
    .jobs.required.name == "required"
    and (.jobs.required.needs | join(",")) == "flake-eval,linux,darwin"
    and .jobs.required.if == "always()"
  ' "$CI_WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "private and production smoke checks overlap after setup" {
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
    | (.jobs.smoke.steps | to_entries | map(select(
      .value.name == "Wait for live upstream contracts"
    ))[0].key) as $wait
    | [
        ($build < $private),
        ($private < $clone),
        ($clone < $production),
        ($production < $wait),
        ($wait < $final),
        ([.jobs.smoke.steps[] | select(
          .name == "Check live upstream contracts"
        )][0].id == "live-upstream"),
        ([.jobs.smoke.steps[] | select(
          .name == "Check live upstream contracts"
        )][0].background == true),
        ([.jobs.smoke.steps[] | select(
          .name == "Wait for live upstream contracts"
        )][0].wait == "live-upstream"),
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
  [[ "$build_script" == *'--print-out-paths'* ]]
  [[ "$build_script" != *'--print-build-logs'* ]]
  [[ "$build_script" != *'--show-trace'* ]]
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
