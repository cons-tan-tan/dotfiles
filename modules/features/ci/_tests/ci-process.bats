#!/usr/bin/env bats

DOTFILES_TEST_REPO_ROOT=${DOTFILES_TEST_REPO_ROOT:-$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)}
source "$DOTFILES_TEST_REPO_ROOT/modules/features/checks/_interface/bats/test-helper.bash"

setup() {
  export PYTHONDONTWRITEBYTECODE=1
  REPO_ROOT="$DOTFILES_TEST_REPO_ROOT"
  CI_SCRIPT_DIR="$REPO_ROOT/modules/features/ci/_scripts"
  HESTIA_MATRIX_OPTIMIZER="$CI_SCRIPT_DIR/optimize_hestia_matrix.py"
  HESTIA_MATRIX_VALIDATOR="$CI_SCRIPT_DIR/validate_hestia_matrix.py"
  SUBSTITUTER_CHECK_SCRIPT="$CI_SCRIPT_DIR/verify_binary_substituters.sh"
  TELEMETRY_SCHEMA="$REPO_ROOT/modules/features/ci/_schemas/telemetry-v1.schema.json"
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

run_hestia_matrix_optimization() {
  local matrix=$1
  local nix_status=${2:-0}
  local stub_dir="$BATS_TEST_TMPDIR/matrix-optimizer-stubs"
  MATRIX_OUTPUT="$BATS_TEST_TMPDIR/optimized-matrix-output"
  EVAL_CAPTURE="$BATS_TEST_TMPDIR/hestia-eval.jsonl"
  LANE_OUTPUT="$BATS_TEST_TMPDIR/lane-x86_64-linux.json"
  : >"$MATRIX_OUTPUT"
  mkdir -p "$stub_dir"

  jq -c '.include[] | .installables / " " | .[] | {
    attr: (. | capture("-(?<name>[^/]+)\\.drv\\^\\*").name),
    drvPath: sub("\\^\\*$"; ""),
    system: "x86_64-linux",
    isCached: false
  }' <<<"$matrix" >"$EVAL_CAPTURE"

  write_bash_stub "$stub_dir/nix" <<'SH'
if [[ ${1:-} == --version ]]; then
  printf 'nix (Nix) 2.34.0\n'
  exit 0
fi
if [[ $OPTIMIZER_NIX_STATUS -ne 0 ]]; then
  printf 'dry-run failed\n' >&2
  exit "$OPTIMIZER_NIX_STATUS"
fi
index=0
for suffix in shared-1 shared-2 config-1 config-2 config-3 config-4 config-5 config-6 config-7 config-8 eval-1 quality-1; do
  index=$((index + 1))
  printf '  /nix/store/%032d-%s.drv\n' "$index" "$suffix" >&2
done
printf '[]\n'
SH
  write_bash_stub "$stub_dir/nix-store" <<'SH'
case "$3" in
  *-configurations.drv)
    index=0
    for suffix in shared-1 shared-2 config-1 config-2 config-3 config-4 config-5 config-6 config-7 config-8; do
      index=$((index + 1))
      printf '/nix/store/%032d-%s.drv\n' "$index" "$suffix"
    done
    ;;
  *-eval-tests.drv)
    printf '/nix/store/%032d-shared-1.drv\n' 1
    printf '/nix/store/%032d-shared-2.drv\n' 2
    printf '/nix/store/%032d-eval-1.drv\n' 11
    ;;
  *-quality.drv)
    printf '/nix/store/%032d-quality-1.drv\n' 12
    ;;
esac
SH

  run env \
    CI_TELEMETRY_LANE="$LANE_OUTPUT" \
    GITHUB_OUTPUT="$MATRIX_OUTPUT" \
    HESTIA_ANY_JOBS=true \
    HESTIA_EVAL_CAPTURE="$EVAL_CAPTURE" \
    HESTIA_MANIFEST_VERSION=12 \
    HESTIA_MATRIX="$matrix" \
    MATRIX_OPTIMIZER_CRITICAL_PATH_SLACK=0.1 \
    MATRIX_OPTIMIZER_MAX_WORKERS=1 \
    MATRIX_OPTIMIZER_MIN_SHARED_DERIVATIONS=2 \
    MATRIX_OPTIMIZER_MIN_SHARED_RATIO=0.5 \
    OPTIMIZER_NIX_STATUS="$nix_status" \
    PATH="$stub_dir:$PATH" \
    SYSTEM=x86_64-linux \
    TELEMETRY_ATTR_PREFIX=lib.hestiaJobs.ci.x86_64-linux \
    TELEMETRY_RUNNER_NAME='GitHub Actions test' \
    python3 "$HESTIA_MATRIX_OPTIMIZER"
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

@test "system matrix optimization merges only beneficial static groups" {
  local matrix='{"include":[{"drvPath":"/nix/store/00000000000000000000000000000000-configurations.drv","system":"x86_64-linux","name":"configurations","os":["ubuntu-latest"],"installables":"/nix/store/00000000000000000000000000000000-configurations.drv^*"},{"drvPath":"/nix/store/11111111111111111111111111111111-eval-tests.drv","system":"x86_64-linux","name":"eval-tests","os":["ubuntu-latest"],"installables":"/nix/store/11111111111111111111111111111111-eval-tests.drv^*"},{"drvPath":"/nix/store/22222222222222222222222222222222-quality.drv","system":"x86_64-linux","name":"quality","os":["ubuntu-latest"],"installables":"/nix/store/22222222222222222222222222222222-quality.drv^*"}]}'

  run_hestia_matrix_optimization "$matrix"
  [ "$status" -eq 0 ]
  run jq -e '
    .include | length == 2
    and .[0].name == "configurations+eval-tests"
    and (.[0].installables | contains("configurations.drv^*"))
    and (.[0].installables | contains("eval-tests.drv^*"))
    and .[1].name == "quality"
  ' <<<"$(sed -n 's/^matrix=//p' "$MATRIX_OUTPUT")"
  [ "$status" -eq 0 ]
  run jq -e '
    (.data.checks | map({key: .display_name, value: (.plan.dependency_drv_ids | length)}) | from_entries)
      == {configurations: 10, "eval-tests": 3, quality: 1}
    and .data.workflow_job
      == {role: "system-evaluate", runner_name: "GitHub Actions test"}
  ' "$LANE_OUTPUT"
  [ "$status" -eq 0 ]
  if command -v check-jsonschema >/dev/null; then
    run check-jsonschema --schemafile "$TELEMETRY_SCHEMA" "$LANE_OUTPUT"
    [ "$status" -eq 0 ]
  fi
}

@test "system matrix optimization falls back after a dry-run failure" {
  local matrix='{"include":[{"drvPath":"/nix/store/00000000000000000000000000000000-configurations.drv","system":"x86_64-linux","name":"configurations","os":["ubuntu-latest"],"installables":"/nix/store/00000000000000000000000000000000-configurations.drv^*"},{"drvPath":"/nix/store/11111111111111111111111111111111-eval-tests.drv","system":"x86_64-linux","name":"eval-tests","os":["ubuntu-latest"],"installables":"/nix/store/11111111111111111111111111111111-eval-tests.drv^*"}]}'

  run_hestia_matrix_optimization "$matrix" 1
  [ "$status" -eq 0 ]
  [[ $output == *"Hestia matrix optimization skipped"* ]]
  run jq -e --argjson original "$matrix" '
    (([.include[].installables] | sort)
      == ([$original.include[].installables] | sort))
    and (([.include[].name] | sort)
      == ([$original.include[].name] | sort))
  ' <<<"$(sed -n 's/^matrix=//p' "$MATRIX_OUTPUT")"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.data.decision.status' "$LANE_OUTPUT")" = fallback ]
}

@test "system matrix validation requires a matching manifest registration" {
  local linux='{"include":[{"drvPath":"/nix/store/linux-a.drv","system":"x86_64-linux","name":"linux-a","os":["ubuntu-latest"],"installables":"/nix/store/linux-a.drv^*"}]}'

  run_hestia_matrix_validation "$linux" 0
  [ "$status" -ne 0 ]
  [[ "$output" == *"Hestia manifest version is invalid for its matrix"* ]]

  run_hestia_matrix_validation "$linux" 12 x86_64-linux false
  [ "$status" -ne 0 ]
  [[ "$output" == *"Hestia any-jobs output does not match its matrix"* ]]
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
  [[ "$output" == *"Hestia matrix is not valid JSON"* ]]

  run_hestia_matrix_validation '{}' 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"Hestia matrix must contain an include array"* ]]

  run_hestia_matrix_validation "$incomplete" 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"Hestia matrix row has invalid build fields"* ]]

  run_hestia_matrix_validation "$invalid_os" 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"Hestia matrix row has invalid build fields"* ]]

  run_hestia_matrix_validation "$duplicate" 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"Hestia matrix contains duplicate drvPaths"* ]]

  run_hestia_matrix_validation "$mixed" 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"Hestia matrix row belongs to another system"* ]]

  oversized=$(jq -cn '{include: [range(257) | {drvPath: ("/nix/store/" + tostring + ".drv"), system: "x86_64-linux", name: ("row-" + tostring), os: ["ubuntu-latest"], installables: ("/nix/store/" + tostring + ".drv^*")}]}')
  run_hestia_matrix_validation "$oversized" 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"Hestia matrix exceeds 256 rows"* ]]

  run_hestia_matrix_validation "$empty" latest
  [ "$status" -ne 0 ]
  [[ "$output" == *"Hestia manifest version is invalid for its matrix"* ]]

  run_hestia_matrix_validation "$linux" 18446744073709551615
  [ "$status" -eq 0 ]
  [ "$(sed -n 's/^manifest-version=//p' "$MATRIX_OUTPUT")" = 18446744073709551615 ]

  run_hestia_matrix_validation "$linux" 18446744073709551616
  [ "$status" -ne 0 ]
  [[ "$output" == *"Hestia manifest version is invalid for its matrix"* ]]

  run_hestia_matrix_validation "$linux" 1 x86_64-linux true 20
  [ "$status" -ne 0 ]
  [[ "$output" == *"Hestia matrix exceeds the GitHub job output limit"* ]]
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
