#!/usr/bin/env bats

setup() {
  REPO_ROOT=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
  WORKFLOW="$REPO_ROOT/.github/workflows/update-pins-smoke.yaml"
  CI_WORKFLOW="$REPO_ROOT/.github/workflows/ci.yaml"
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
      == "actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0"
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
  [[ "$private_script" == *'/bin/update-pins-smoke'* ]]
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
