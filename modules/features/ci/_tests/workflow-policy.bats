#!/usr/bin/env bats

DOTFILES_TEST_REPO_ROOT=${DOTFILES_TEST_REPO_ROOT:-$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)}

setup() {
  REPO_ROOT="$DOTFILES_TEST_REPO_ROOT"
  WORKFLOW_DIR="$REPO_ROOT/.github/workflows"
  WORKFLOW="$WORKFLOW_DIR/update-pins-smoke.yaml"
  CI_WORKFLOW="$WORKFLOW_DIR/ci.yaml"
  TELEMETRY_WORKFLOW="$WORKFLOW_DIR/ci-telemetry.yaml"
  HESTIA_WORKFLOW="$WORKFLOW_DIR/hestia-system.yaml"
  CACHE_GC_WORKFLOW="$WORKFLOW_DIR/cache-gc.yaml"
  CACHE_SETTINGS="$REPO_ROOT/modules/features/platform/nix-settings/_data/cache.nix"
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
      and ((.permissions.actions // "read") == "read")
      and ([.permissions | keys[] | select(. != "contents" and . != "actions")]
        | length) == 0
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
    if [[ $(basename "$workflow") == cache-gc.yaml ]]; then
      yq -e '
        .jobs.gc.permissions.actions == "write"
        and .jobs.gc.permissions.contents == "read"
        and (.jobs.gc.permissions | length) == 2
        and ([.jobs[] | .permissions // null] |
          map(select(. != null)) | length) == 1
      ' "$workflow" >/dev/null || return 1
    else
      yq -e '
        ([.jobs[] | .permissions // null] | map(select(. != null)) | length) == 0
      ' "$workflow" >/dev/null || return 1
    fi
    checkout_count=$((checkout_count + $(yq -r '[.. | select(kind == "map") | select(
      (.uses // "") | test("^actions/checkout@")
    )] | length' "$workflow")))
    if [[ -n "$visited_file" ]]; then
      basename "$workflow" >>"$visited_file"
    fi
  done

  ((checkout_count > 0))
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
      .run == "bash modules/features/ci/_scripts/update_pins_smoke.sh create-checkout"
    )][0].env.UPDATE_PINS_CHECKOUT)
      == "${{ runner.temp }}/update-pins-check"
    and ([.jobs.smoke.steps[] | select(
      (.uses // "") | test("^actions/checkout@")
    )][0].with."persist-credentials") == false
    and ([.jobs.smoke.steps[] | has("continue-on-error") | not] | all)
  ' "$WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "all discovered workflows follow the universal policy" {
  check_universal_workflow_policy "$WORKFLOW_DIR"
}

@test "step ids are only declared for workflow data flow" {
  local id
  local workflow
  while IFS= read -r workflow; do
    while IFS= read -r id; do
      if env STEP_REF="steps.$id." yq -e '
        [.. | select(tag == "!!str") | select(contains(strenv(STEP_REF)))]
          | length > 0
      ' "$workflow" >/dev/null; then
        continue
      fi
      run env STEP_ID="$id" yq -e '
        [.jobs[].steps[]? | select(.wait == strenv(STEP_ID))] | length > 0
      ' "$workflow"
      [ "$status" -eq 0 ]
    done < <(yq -r '.jobs[].steps[]?.id // "" | select(length > 0)' "$workflow")
  done < <(workflow_files "$WORKFLOW_DIR")
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

@test "universal policy rejects undeclared job permission escalation" {
  local fixture_dir="$BATS_TEST_TMPDIR/job-permissions-workflow"
  mkdir -p "$fixture_dir"

  cat >"$fixture_dir/escalated.yaml" <<'YAML'
on: push
permissions:
  contents: read
jobs:
  check:
    permissions:
      actions: write
      contents: read
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - name: Check out repository
        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1
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
      ([.jobs.smoke.steps[] | select(.id == "live-upstream")][0].env.UPDATE_PINS_SMOKE
        == "${{ steps.build.outputs.path }}/bin/update-pins-smoke")
    ] | all
  ' "$WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "Hestia workflow inputs stay aligned with the CI defaults" {
  local cache_gc_action
  local matrix_action
  local smoke_action
  local system_action
  local version
  local upstream_key_names
  version=$(yq -r '.env.HESTIA_VERSION' "$HESTIA_WORKFLOW")
  upstream_key_names=$(yq -r '.env.HESTIA_UPSTREAM_CACHE_KEY_NAMES' "$HESTIA_WORKFLOW")
  smoke_action=$(yq -r '.jobs.smoke.steps[] | select((.uses // "") | test("^Mic92/hestia@")) | .uses' "$WORKFLOW")
  system_action=$(yq -r '.jobs.evaluate.steps[] | select((.uses // "") | test("^Mic92/hestia@")) | .uses' "$HESTIA_WORKFLOW")
  matrix_action=$(yq -r '.jobs.evaluate.steps[] | select(.id == "hestia-matrix") | .uses' "$HESTIA_WORKFLOW")
  cache_gc_action=$(yq -r '.jobs.gc.steps[] | select((.uses // "") | test("^Mic92/hestia@")) | .uses' "$CACHE_GC_WORKFLOW")

  [ "$smoke_action" = "$system_action" ]
  [ "$cache_gc_action" = "$system_action" ]
  [ "${system_action##*@}" = "${matrix_action##*@}" ]
  [ "$(yq -r '.jobs.smoke.steps[] | select((.uses // "") | test("^Mic92/hestia@")) | .with.version' "$WORKFLOW")" = "$version" ]
  [ "$(yq -r '.jobs.smoke.steps[] | select((.uses // "") | test("^Mic92/hestia@")) | .with."upstream-cache-filter"' "$WORKFLOW")" = true ]
  [ "$(yq -r '.jobs.smoke.steps[] | select((.uses // "") | test("^Mic92/hestia@")) | .with."upstream-cache-key-names"' "$WORKFLOW")" = "$upstream_key_names" ]
  [ "$(yq -r '.jobs.gc.steps[] | select((.uses // "") | test("^Mic92/hestia@")) | .with.version' "$CACHE_GC_WORKFLOW")" = "$version" ]
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
      (.uses // "") | test("^Mic92/hestia@")
    )] | length) == 1
    and ([.jobs.evaluate.steps[] | select(.id == "hestia-matrix")] | length) == 1
    and ([.jobs.evaluate.steps[] | select(.id == "hestia-matrix")][0].uses
      | test("^Mic92/hestia/matrix@"))
    and ([.jobs.evaluate.steps[] | select(.id == "hestia-matrix")][0].with.flake)
      == ".#hydraJobs.ci.${{ inputs.system }}"
    and ([.jobs.evaluate.steps[] | select(.id == "hestia-matrix")][0].with."attr-prefix")
      == "hydraJobs.ci.${{ inputs.system }}"
    and ([.jobs.evaluate.steps[] | select(.id == "hestia-matrix")][0].with."nix-eval-jobs"
      == "python3 modules/features/ci/_scripts/capture_hestia_eval.py")
    and ([.jobs.evaluate.steps[] | select(.id == "hestia-matrix")][0].env.HESTIA_EVAL_CAPTURE)
      == "${{ runner.temp }}/ci-telemetry/hestia-eval.jsonl"
    and ([.jobs.evaluate.steps[] | select(.id == "matrix")]
      | length) == 1
    and ([.jobs.evaluate.steps[] | select(.id == "optimized-matrix")]
      | length) == 1
    and ([.jobs.evaluate.steps[] | select(.id == "optimized-matrix")][0].env.HESTIA_MATRIX)
      == "${{ steps.hestia-matrix.outputs.matrix }}"
    and ([.jobs.evaluate.steps[] | select(.id == "optimized-matrix")][0].run)
      == "python3 modules/features/ci/_scripts/optimize_hestia_matrix.py"
    and ([.jobs.evaluate.steps[] | select(.id == "matrix")][0].run)
      == "python3 modules/features/ci/_scripts/validate_hestia_matrix.py"
    and ([.jobs.evaluate.steps[] | select(.id == "matrix")][0].env.HESTIA_MATRIX)
      == "${{ steps.optimized-matrix.outputs.matrix }}"
    and ([.jobs.evaluate.steps[] | select(.id == "matrix")][0].env.HESTIA_ORIGINAL_MATRIX)
      == "${{ steps.hestia-matrix.outputs.matrix }}"
  ' "$HESTIA_WORKFLOW"
  [ "$status" -eq 0 ]
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
      (.uses // "") | test("^Mic92/hestia@")
    )][0].with."wait-manifest-version")
      == "${{ needs.evaluate.outputs.manifest-version }}"
    and ([.jobs.build.steps[] | select(
      .run == "python3 modules/features/ci/_scripts/run_hestia_build.py"
    )][0].env.INSTALLABLES)
      == "${{ matrix.installables }}"
    and ([.jobs.build.steps[] | select(
      .run == "python3 modules/features/ci/_scripts/run_hestia_build.py"
    )][0].env.TELEMETRY_JOB_ID)
      == "${{ matrix.jobId }}"
    and ([.jobs.build.steps[] | select(
      .run == "bash modules/features/ci/_scripts/verify_binary_substituters.sh"
    )] | length) == 1
    and ([.jobs.build.steps[] | select(
      (.uses // "") | test("^actions/checkout@")
    )][0].with."persist-credentials" == false)
    and ([.jobs.build.steps[] | select(
      (.uses // "") | test("^actions/checkout@")
    )][0].with."sparse-checkout")
      == "modules/features/ci/_scripts"
  ' "$HESTIA_WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "system lane persists versioned telemetry without gating builds" {
  run yq -e '
    [
      ([.jobs.evaluate.steps[] | select(
        (.uses // "") | test("^actions/upload-artifact@")
      )][0].if
        == "always()"),
      ([.jobs.evaluate.steps[] | select(
        (.uses // "") | test("^actions/upload-artifact@")
      )][0]."continue-on-error"
        == true),
      ([.jobs.evaluate.steps[] | select(
        (.uses // "") | test("^actions/upload-artifact@")
      )][0].with."retention-days"
        == 7),
      ([.jobs.build.steps[] | select(
        (.uses // "") | test("^actions/upload-artifact@")
      )][0].if
        == "always()"),
      ([.jobs.build.steps[] | select(
        (.uses // "") | test("^actions/upload-artifact@")
      )][0]."continue-on-error"
        == true),
      ([.jobs.build.steps[] | select(
        (.uses // "") | test("^actions/upload-artifact@")
      )][0].with."retention-days"
        == 7),
      ([.jobs.result.steps[] | select(
        ((.uses // "") | test("^actions/(download|upload)-artifact@"))
        or ((.run // "") | contains("telemetry"))
      )] | length) == 0
    ] | all
  ' "$HESTIA_WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "completed CI runs are collected independently with attempt isolation" {
  run yq -e '
    (.on.workflow_run.workflows | length) == 1
    and .on.workflow_run.workflows[0] == "CI"
    and (.on.workflow_run.types | length) == 1
    and .on.workflow_run.types[0] == "completed"
    and (.on.workflow_run.branches | length) == 1
    and .on.workflow_run.branches[0] == "main"
    and .concurrency.group
      == "ci-telemetry-${{ github.event.workflow_run.id }}-${{ github.event.workflow_run.run_attempt }}"
    and .concurrency."cancel-in-progress" == false
    and .permissions.actions == "read"
    and .permissions.contents == "read"
    and (.permissions | length) == 2
    and (.jobs.collect.if | contains("github.event.workflow_run.event == '\''push'\''"))
    and (.jobs.collect.if | contains("github.event.workflow_run.event == '\''workflow_dispatch'\''"))
    and ([.jobs.collect.steps[] | select(
      (.uses // "") | test("^actions/checkout@")
    )][0].with.ref
      == "${{ github.sha }}")
    and ([.jobs.collect.steps[] | select(
      (.uses // "") | test("^actions/checkout@")
    )][0].with."sparse-checkout"
      | contains("modules/features/ci/_schemas"))
    and ([.jobs.collect.steps[] | select(.id == "download")][0]."continue-on-error"
      == true)
    and ([.jobs.collect.steps[] | select(.id == "download")][0].with.pattern
      == "ci-telemetry-fragment-${{ github.event.workflow_run.id }}-${{ github.event.workflow_run.run_attempt }}-*")
    and ([.jobs.collect.steps[] | select(.id == "download")][0].with."run-id"
      == "${{ github.event.workflow_run.id }}")
    and ([.jobs.collect.steps[] | select(.id == "download")][0].with."github-token"
      == "${{ github.token }}")
    and ([.jobs.collect.steps[] | select(.id == "download")][0].with."merge-multiple"
      == false)
    and ([.jobs.collect.steps[] | select(
      (.run // "") | contains("collect_ci_telemetry.py")
    )][0].run
      | contains("collect_ci_telemetry.py"))
    and ([.jobs.collect.steps[] | select(
      (.run // "") | contains("collect_ci_telemetry.py")
    )][0].env.TELEMETRY_DOWNLOAD_OUTCOME
      == "${{ steps.download.outcome }}")
    and ([.jobs.collect.steps[] | select(
      (.run // "") | contains("collect_ci_telemetry.py")
    )][0].run
      | contains("--download-outcome \"$TELEMETRY_DOWNLOAD_OUTCOME\""))
    and ([.jobs.collect.steps[] | select(
      (.run // "") | contains("collect_ci_telemetry.py")
    )][0].run
      | contains("--system aarch64-darwin"))
    and ([.jobs.collect.steps[] | select(
      (.run // "") | contains("collect_ci_telemetry.py")
    )][0].run
      | contains("--system x86_64-linux"))
    and ([.jobs.collect.steps[] | select(
      (.uses // "") | test("^actions/upload-artifact@")
    )][0].with.name
      | contains("source-${{ github.event.workflow_run.id }}-${{ github.event.workflow_run.run_attempt }}"))
    and ([.jobs.collect.steps[] | select(
      (.uses // "") | test("^actions/upload-artifact@")
    )][0].with.name
      | contains("collector-${{ github.run_id }}-${{ github.run_attempt }}"))
    and ([.jobs.collect.steps[] | select(
      (.uses // "") | test("^actions/upload-artifact@")
    )][0].with."retention-days"
      == 90)
  ' "$TELEMETRY_WORKFLOW"
  [ "$status" -eq 0 ]
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
      and .env.HESTIA_UPSTREAM_CACHE_KEY_NAMES
        == strenv(EXPECTED_HESTIA_KEY_NAMES)
    ' "$HESTIA_WORKFLOW"
  [ "$status" -eq 0 ]

  run yq -e '
    ([
      .jobs.evaluate.steps[],
      .jobs.build.steps[]
    ] | map(select((.uses // "") | test("^nixbuild/nix-quick-install-action@")))
      | length) == 2
    and ([
      .jobs.evaluate.steps[],
      .jobs.build.steps[]
    ] | map(select((.uses // "") | test("^nixbuild/nix-quick-install-action@")))
      | map(select(.with.nix_conf | contains("${{ env.NIX_EXTRA_SUBSTITUTERS }}")))
      | length) == 2
    and ([
      .jobs.evaluate.steps[],
      .jobs.build.steps[]
    ] | map(select((.uses // "") | test("^nixbuild/nix-quick-install-action@")))
      | map(select(.with.nix_conf | contains("${{ env.NIX_EXTRA_TRUSTED_PUBLIC_KEYS }}")))
      | length) == 2
    and ([
      .jobs[].steps[]?
    ] | map(select(
      ((.uses // "") | test("^Mic92/hestia@"))
      and .with.version == "${{ env.HESTIA_VERSION }}"
      and .with."upstream-cache-filter" == true
      and .with."upstream-cache-key-names"
        == "${{ env.HESTIA_UPSTREAM_CACHE_KEY_NAMES }}"
    )) | length) == 2
    and (.jobs.result.needs | join(",")) == "evaluate,build"
    and .jobs.result.if == "always()"
    and ([.jobs.result.steps[] | select(
      (.uses // "") | test("^actions/checkout@")
    )][0].with."persist-credentials") == false
    and ([.jobs.result.steps[] | select(
      (.uses // "") | test("^actions/checkout@")
    )][0].with."sparse-checkout") == "modules/features/ci/_scripts"
    and ([.jobs.result.steps[] | select(
      .run == "bash modules/features/ci/_scripts/verify_hestia_result.sh"
    )] | length) == 1
  ' "$HESTIA_WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "required result depends on every independent lane" {
  run yq -e '
    .jobs.required.name == "required"
    and (.jobs.required.needs | join(",")) == "flake-eval,linux,darwin"
    and .jobs.required.if == "always()"
    and ([.jobs.required.steps[] | select(
      (.uses // "") | test("^actions/checkout@")
    )][0].with."persist-credentials") == false
    and ([.jobs.required.steps[] | select(
      (.uses // "") | test("^actions/checkout@")
    )][0].with."sparse-checkout") == "modules/features/ci/_scripts"
    and ([.jobs.required.steps[] | select(
      .run == "bash modules/features/ci/_scripts/verify_required_results.sh"
    )] | length) == 1
  ' "$CI_WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "private and production smoke checks overlap after setup" {
  run yq -e '
    (.jobs.smoke.steps | length) as $count
    | (.jobs.smoke.steps | to_entries | map(select(
      .value.run == "bash modules/features/ci/_scripts/update_pins_smoke.sh build-private"
    ))[0].key) as $build
    | (.jobs.smoke.steps | to_entries | map(select(.value.id == "live-upstream"))[0].key) as $private
    | (.jobs.smoke.steps | to_entries | map(select(
      .value.run == "bash modules/features/ci/_scripts/update_pins_smoke.sh create-checkout"
    ))[0].key) as $clone
    | (.jobs.smoke.steps | to_entries | map(select(
      .value.run == "bash modules/features/ci/_scripts/update_pins_smoke.sh exercise-updater"
    ))[0].key) as $production
    | (.jobs.smoke.steps | to_entries | map(select(
      .value.run == "bash modules/features/ci/_scripts/update_pins_smoke.sh verify-original"
    ))[0].key) as $final
    | (.jobs.smoke.steps | to_entries | map(select(
      .value.wait == "live-upstream"
    ))[0].key) as $wait
    | [
        ($build < $private),
        ($private < $clone),
        ($clone < $production),
        ($production < $wait),
        ($wait < $final),
        ([.jobs.smoke.steps[] | select(.id == "live-upstream")][0].background == true),
        ([.jobs.smoke.steps[] | select(.wait == "live-upstream")] | length) == 1,
        ($final == ($count - 1))
      ]
      | all
  ' "$WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "smoke workflow delegates behavior to the process script" {
  run yq -e '
    ([.jobs.smoke.steps[].run // "" | select(
      contains("modules/features/ci/_scripts/update_pins_smoke.sh")
    )] | sort | join("|")) == (
      "bash modules/features/ci/_scripts/update_pins_smoke.sh build-private|"
      + "bash modules/features/ci/_scripts/update_pins_smoke.sh create-checkout|"
      + "bash modules/features/ci/_scripts/update_pins_smoke.sh exercise-updater|"
      + "bash modules/features/ci/_scripts/update_pins_smoke.sh live-upstream|"
      + "bash modules/features/ci/_scripts/update_pins_smoke.sh verify-original"
    )
  ' "$WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "production updater runs in a bounded disposable checkout" {
  run yq -e '
    ([.jobs.smoke.steps[] | select(
      .run == "bash modules/features/ci/_scripts/update_pins_smoke.sh create-checkout"
    )][0].env.UPDATE_PINS_CHECKOUT)
      == "${{ runner.temp }}/update-pins-check"
    and ([.jobs.smoke.steps[] | select(
      .run == "bash modules/features/ci/_scripts/update_pins_smoke.sh exercise-updater"
    )][0].working-directory)
      == "${{ runner.temp }}/update-pins-check"
  ' "$WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "original checkout is checked even after a smoke failure" {
  run yq -e '
    ([.jobs.smoke.steps[] | select(
      .run == "bash modules/features/ci/_scripts/update_pins_smoke.sh verify-original"
    )][0].if) == "always()"
  ' "$WORKFLOW"
  [ "$status" -eq 0 ]
}
