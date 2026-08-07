#!/usr/bin/env bats

DOTFILES_TEST_REPO_ROOT=${DOTFILES_TEST_REPO_ROOT:-$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)}

setup() {
  REPO_ROOT="$DOTFILES_TEST_REPO_ROOT"
  WORKFLOW_DIR="$REPO_ROOT/.github/workflows"
  CI_WORKFLOW="$WORKFLOW_DIR/ci.yaml"
  TELEMETRY_WORKFLOW="$WORKFLOW_DIR/ci-telemetry.yaml"
  HESTIA_WORKFLOW="$WORKFLOW_DIR/hestia-system.yaml"
  CACHE_GC_WORKFLOW="$WORKFLOW_DIR/cache-gc.yaml"
  HESTIA_SETUP_ACTION="$REPO_ROOT/.github/actions/setup-hestia/action.yaml"
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
        ((has("name") and (.name | tag == "!!str" and length > 0))
          or has("parallel") or has("wait") or has("wait-all") or has("cancel"))]
        | all)
      and ([.jobs[] | .steps[]? | select(has("parallel")) | .parallel[] |
        (has("name") and (.name | tag == "!!str" and length > 0))] | all)
      and ([.. | select(kind == "map") | .uses // "" | select(length > 0)
        | select(test("^(\\./|\\$/)") | not)
        | test("@[0-9a-f]{40}$")] | all)
      and ([.. | select(kind == "map") | .uses // "" |
        select(test("^(\\./|\\$/)")) |
        test("^\\$/\\.github/(actions/[a-z0-9-]+|workflows/[a-z0-9-]+\\.yaml)$")]
        | all)
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

@test "universal policy only accepts self-repository local references" {
  local fixture_dir="$BATS_TEST_TMPDIR/self-references"
  local reference
  mkdir -p "$fixture_dir"

  cat >"$fixture_dir/workflow.yaml" <<'YAML'
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
      - name: Set up local action
        uses: $/.github/actions/setup-hestia
YAML

  check_universal_workflow_policy "$fixture_dir"

  for reference in \
    './.github/actions/setup-hestia' \
    '$/.github/actions/../setup-hestia'; do
    env SELF_REFERENCE="$reference" yq -i '
      .jobs.check.steps[] |= select(.name == "Set up local action").uses = strenv(SELF_REFERENCE)
    ' "$fixture_dir/workflow.yaml"
    run check_universal_workflow_policy "$fixture_dir"
    [ "$status" -ne 0 ]
  done
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

@test "Hestia workflow versions stay aligned" {
  local cache_gc_action
  local matrix_action
  local setup_action
  local version
  version=$(yq -r '.runs.steps[] | select((.uses // "") | test("^Mic92/hestia@")) | .with.version' "$HESTIA_SETUP_ACTION")
  setup_action=$(yq -r '.runs.steps[] | select((.uses // "") | test("^Mic92/hestia@")) | .uses' "$HESTIA_SETUP_ACTION")
  matrix_action=$(yq -r '.jobs.evaluate.steps[] | select(.id == "hestia-matrix") | .uses' "$HESTIA_WORKFLOW")
  cache_gc_action=$(yq -r '.jobs.gc.steps[] | select((.uses // "") == "$/.github/actions/setup-hestia") | .uses' "$CACHE_GC_WORKFLOW")

  [ "$cache_gc_action" = '$/.github/actions/setup-hestia' ]
  [ "${setup_action##*@}" = "${matrix_action##*@}" ]
  [ "$version" = "v3.0.0" ]
  [ "$(yq -r '.jobs.gc.steps[] | select(.uses == "$/.github/actions/setup-hestia") | .with."upstream-cache-filter"' "$CACHE_GC_WORKFLOW")" = "false" ]
}

@test "Hestia setup action composes pinned dependencies" {
  run yq -e '
    .name == "Set up Nix and Hestia"
    and (.description | length) > 0
    and .runs.using == "composite"
    and .inputs."upstream-cache-filter".default == "true"
    and .inputs."wait-manifest-version".default == "0"
    and .outputs."nix-extra-substituters".value
      == "https://cache.numtide.com https://nix-community.cachix.org"
    and .outputs."hestia-version".value == "v3.0.0"
    and ([.runs.steps[] | has("name")] | all)
    and ([.runs.steps[] | .uses // "" | select(length > 0)
      | test("@[0-9a-f]{40}$")] | all)
    and ([.runs.steps[] | select(
      (.uses // "") | test("^nixbuild/nix-quick-install-action@")
    )] | length) == 1
    and ([.runs.steps[] | select(
      (.uses // "") | test("^Mic92/hestia@")
    )] | length) == 1
    and ([.runs.steps[] | select(
      (.uses // "") | test("^Mic92/hestia@")
    )][0].with."upstream-cache-filter")
      == "${{ inputs.upstream-cache-filter }}"
    and ([.runs.steps[] | select(
      (.uses // "") | test("^Mic92/hestia@")
    )][0].with."upstream-cache-key-names" | sub("[[:space:]]+"; " "))
      == "${{ inputs.upstream-cache-filter == '\''true'\'' && '\''cache.nixos.org-1 niks3.numtide.com-1 nix-community.cachix.org-1'\'' || '\'''\'' }}"
    and ([.runs.steps[] | select(
      (.uses // "") | test("^Mic92/hestia@")
    )][0].with."wait-manifest-version")
      == "${{ inputs.wait-manifest-version }}"
  ' "$HESTIA_SETUP_ACTION"
  [ "$status" -eq 0 ]
}

@test "flake evaluation and system lanes start independently" {
  run yq -e '
    .jobs."flake-eval".name == "evaluate / flake"
    and .jobs."flake-eval".runs-on == "ubuntu-latest"
    and .jobs."flake-eval".needs == null
    and ([.jobs."flake-eval".steps[] | select(.id == "checkout")][0].background
      == true)
    and ([.jobs."flake-eval".steps[] | select(.wait == "checkout")]
      | length) == 1
    and .jobs.linux.name == "linux"
    and .jobs.linux.uses == "$/.github/workflows/hestia-system.yaml"
    and .jobs.linux.with.system == "x86_64-linux"
    and .jobs.linux.needs == null
    and .jobs.darwin.name == "darwin"
    and .jobs.darwin.uses == "$/.github/workflows/hestia-system.yaml"
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
      .uses == "$/.github/actions/setup-hestia"
    )] | length) == 1
    and ([.jobs.evaluate.steps[] | select(
      .uses == "$/.github/actions/setup-hestia"
    )][0].id) == "setup-hestia"
    and ([.jobs.evaluate.steps[] | select(.id == "checkout")][0].background
      == true)
    and ([.jobs.evaluate.steps[] | select(.wait == "checkout")]
      | length) == 1
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
    and ([.jobs.evaluate.steps[] | select(.id == "optimized-matrix")][0].env.HESTIA_VERSION)
      == "${{ steps.setup-hestia.outputs.hestia-version }}"
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
      .uses == "$/.github/actions/setup-hestia"
    )][0].id) == "setup-hestia"
    and ([.jobs.build.steps[] | select(
      .uses == "$/.github/actions/setup-hestia"
    )][0].with."wait-manifest-version")
      == "${{ needs.evaluate.outputs.manifest-version }}"
    and ([.jobs.build.steps[] | select(.id == "checkout")][0].background
      == true)
    and ([.jobs.build.steps[] | select(.wait == "checkout")]
      | length) == 1
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
      .run == "bash modules/features/ci/_scripts/verify_binary_substituters.sh"
    )][0].env.NIX_EXTRA_SUBSTITUTERS)
      == "${{ steps.setup-hestia.outputs.nix-extra-substituters }}"
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
      )][0].background
        == true),
      (([.jobs.evaluate.steps[] | select(
        .wait == "upload-evaluation-telemetry"
      )] | length) == 1),
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
    (.jobs.collect.steps | [.. | select(kind == "map") | select(has("name"))])
      as $steps
    | ([.jobs.collect.steps[] | select(has("parallel"))]) as $parallel_groups
    | $parallel_groups[0].parallel as $telemetry_publish
    | $parallel_groups[1].parallel as $optimization_inputs
    | [
        ((.on.workflow_run.workflows | length) == 1),
        (.on.workflow_run.workflows[0] == "CI"),
        ((.on.workflow_run.types | length) == 1),
        (.on.workflow_run.types[0] == "completed"),
        ((.on.workflow_run.branches | length) == 1),
        (.on.workflow_run.branches[0] == "main"),
        (.concurrency.group
          == "ci-telemetry-${{ github.event.workflow_run.id }}-${{ github.event.workflow_run.run_attempt }}"),
        (.concurrency."cancel-in-progress" == false),
        (.permissions.actions == "read"),
        (.permissions.contents == "read"),
        ((.permissions | length) == 2),
        (.jobs.collect.if | contains("github.event.workflow_run.event == '\''push'\''")),
        (.jobs.collect.if | contains("github.event.workflow_run.event == '\''workflow_dispatch'\''")),
        ([$steps[] | select(
          (.uses // "") | test("^actions/checkout@")
        )][0].with.ref == "${{ github.sha }}"),
        ([$steps[] | select(
          (.uses // "") | test("^actions/checkout@")
        )][0].with | has("sparse-checkout") | not),
        ([$steps[] | select(.id == "download")][0]."continue-on-error" == true),
        ([$steps[] | select(.id == "download")][0].with.pattern
          == "ci-telemetry-fragment-${{ github.event.workflow_run.id }}-${{ github.event.workflow_run.run_attempt }}-*"),
        ([$steps[] | select(.id == "download")][0].with."run-id"
          == "${{ github.event.workflow_run.id }}"),
        ([$steps[] | select(.id == "download")][0].with."github-token"
          == "${{ github.token }}"),
        ([$steps[] | select(.id == "download")][0].with."merge-multiple" == false),
        ([$steps[] | select(
          (.run // "") | contains("collect_ci_telemetry.py")
        )][0].run | contains("collect_ci_telemetry.py")),
        ([$steps[] | select(
          (.run // "") | contains("collect_ci_telemetry.py")
        )][0].env.TELEMETRY_DOWNLOAD_OUTCOME == "${{ steps.download.outcome }}"),
        ([$steps[] | select(
          (.run // "") | contains("collect_ci_telemetry.py")
        )][0].run | contains("--download-outcome \"$TELEMETRY_DOWNLOAD_OUTCOME\"")),
        ([$steps[] | select(
          (.run // "") | contains("collect_ci_telemetry.py")
        )][0].run | contains("--system aarch64-darwin")),
        ([$steps[] | select(
          (.run // "") | contains("collect_ci_telemetry.py")
        )][0].run | contains("--system x86_64-linux")),
        ([$steps[] | select(
          (.run // "") | contains("capture_workflow_timing.py")
        )][0].env.SOURCE_RUN_ATTEMPT == "${{ github.event.workflow_run.run_attempt }}"),
        ([$steps[] | select(
          (.run // "") | contains("capture_workflow_timing.py")
        )][0].run | contains("--run-attempt \"$SOURCE_RUN_ATTEMPT\"")),
        (([$steps[] | select(
          (.run // "") | contains("download_ci_telemetry_history.py")
        )] | length) == 1),
        (([$steps[] | select(.uses == "$/.github/actions/setup-hestia")]
          | length) == 1),
        ([$steps[] | select(.uses == "$/.github/actions/setup-hestia")][0].if
          == "github.event.workflow_run.conclusion == '\''success'\''"),
        ([$steps[] | select(
          (.run // "") | contains("nix profile add")
        )][0].run | contains("modules/features/ci/_packages/matrix-planner/runtime.nix")),
        ([$steps[] | select(
          (.run // "") | contains("plan-ci-matrix")
        )][0].run | contains("--max-jobs-per-system") | not),
        ([$steps[] | select(
          (.uses // "") | test("^actions/upload-artifact@")
        )][0].with.name | contains(
          "source-${{ github.event.workflow_run.id }}-${{ github.event.workflow_run.run_attempt }}"
        )),
        ([$steps[] | select(
          (.uses // "") | test("^actions/upload-artifact@")
        )][0].with.name | contains(
          "collector-${{ github.run_id }}-${{ github.run_attempt }}"
        )),
        (($parallel_groups | length) == 2),
        ([$steps[] | select(.id == "checkout")][0].background == true),
        (([.jobs.collect.steps[] | select(.wait == "checkout")] | length) == 1),
        (($telemetry_publish | length) == 3),
        ($telemetry_publish[0].name == "Upload run telemetry"),
        ($telemetry_publish[1].name == "Capture source workflow timing"),
        ($telemetry_publish[2].name == "Set up Nix and Hestia"),
        (($optimization_inputs | length) == 2),
        ($optimization_inputs[0].name == "Download telemetry history"),
        ($optimization_inputs[1].name == "Install matrix planner"),
        ([$steps[] | select(.name == "Upload run telemetry")][0].if == "always()"),
        (([$steps[] | select(
          (.uses // "") | test("^actions/upload-artifact@")
        )] | length) == 2),
        ([$steps[] | select(
          (.uses // "") | test("^actions/upload-artifact@")
        ) | .with."retention-days" == 90] | all),
        (([$steps[] | select(
          (.uses // "") | test("^actions/upload-artifact@")
        ) | .with.name | select(contains("ci-matrix-plan-v1-source-"))]
          | length) == 1)
      ] | all
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
      ([.runs.steps[] | select(
        (.uses // "") | test("^nixbuild/nix-quick-install-action@")
      )][0].with.nix_conf | split("\n") | map(select(. != "")))
        as $nix_conf_lines
      | [
        (($nix_conf_lines | length) == 2),
        ($nix_conf_lines[0]
          == "extra-substituters = " + strenv(EXPECTED_SUBSTITUTERS)),
        ($nix_conf_lines[1]
          == "extra-trusted-public-keys = " + strenv(EXPECTED_KEYS)),
        (.outputs."nix-extra-substituters".value
          == strenv(EXPECTED_SUBSTITUTERS)),
        (.outputs."hestia-version".value == "v3.0.0"),
        (([.runs.steps[] | select(
          (.uses // "") | test("^nixbuild/nix-quick-install-action@")
        )] | length) == 1),
        (([.runs.steps[] | select(
          (.uses // "") | test("^Mic92/hestia@")
        )][0].with."upstream-cache-key-names" | sub("[[:space:]]+"; " "))
          == "${{ inputs.upstream-cache-filter == '\''true'\'' && '\''"
            + strenv(EXPECTED_HESTIA_KEY_NAMES) + "'\'' || '\'''\'' }}")
      ] | all
    ' "$HESTIA_SETUP_ACTION"
  [ "$status" -eq 0 ]

  run yq -e '
    ([
      .jobs[].steps[]?
    ] | map(select(
      .uses == "$/.github/actions/setup-hestia"
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
