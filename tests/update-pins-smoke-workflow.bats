#!/usr/bin/env bats

setup() {
  REPO_ROOT=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
  WORKFLOW="$REPO_ROOT/.github/workflows/update-pins-smoke.yaml"
  CI_WORKFLOW="$REPO_ROOT/.github/workflows/ci.yaml"
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

@test "upstream smoke workflow has bounded read-only execution" {
  run yq -e '
    .permissions.contents == "read"
    and (.permissions | length) == 1
    and .concurrency.group == "update-pins-upstream-smoke"
    and .concurrency.cancel-in-progress == true
    and .jobs.smoke.timeout-minutes == 20
    and .jobs.smoke.steps[0].uses == "actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0"
    and .jobs.smoke.steps[0].with."persist-credentials" == false
    and ([.jobs.smoke.steps[] | select(.name == "Verify repository remained unchanged")] | length) == 1
    and ([.jobs.smoke.steps[] | select(.name == "Verify repository remained unchanged")][0].if) == "always()"
  ' "$WORKFLOW"
  [ "$status" -eq 0 ]
  ! grep -Fq 'continue-on-error: true' "$WORKFLOW"
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

@test "upstream smoke workflow builds only the private output and checks cleanliness" {
  local script
  script=$(yq -r '[.jobs.smoke.steps[].run // ""] | join("\n")' "$WORKFLOW")

  [[ "$script" == *".#checks.x86_64-linux.update-pins-smoke"* ]]
  [[ "$script" == *'--no-link'* ]]
  [[ "$script" == *'--no-write-lock-file'* ]]
  [[ "$script" == *'/bin/update-pins-smoke'* ]]
  [[ "$script" == *'git diff --exit-code'* ]]
  [[ "$script" == *'git status --short'* ]]
  [[ "$script" != *'nix run .#update-pins'* ]]
  [[ "$script" != *'npm install'* ]]
  [[ "$script" != *'git push'* ]]
}
