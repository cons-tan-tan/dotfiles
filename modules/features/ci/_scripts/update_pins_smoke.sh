#!/usr/bin/env bash

set -euo pipefail

command=${1:-}

case "$command" in
build-private)
  smoke_path="$(
    nix build \
      .#checks.x86_64-linux.update-pins-smoke \
      --no-link \
      --no-write-lock-file \
      --print-out-paths
  )"
  printf 'path=%s\n' "$smoke_path" >>"$GITHUB_OUTPUT"
  ;;
live-upstream)
  cd "$RUNNER_TEMP"
  "$UPDATE_PINS_SMOKE"
  ;;
create-checkout)
  test ! -e "$UPDATE_PINS_CHECKOUT"
  git clone \
    --no-local \
    --no-checkout \
    --single-branch \
    --depth=1 \
    --no-tags \
    "$GITHUB_WORKSPACE" \
    "$UPDATE_PINS_CHECKOUT"
  git -C "$UPDATE_PINS_CHECKOUT" checkout --quiet --detach "$GITHUB_SHA"
  test "$(git -C "$UPDATE_PINS_CHECKOUT" rev-parse HEAD)" = "$GITHUB_SHA"
  git -C "$UPDATE_PINS_CHECKOUT" remote remove origin
  checkout_status="$(git -C "$UPDATE_PINS_CHECKOUT" status --short)"
  test -z "$checkout_status"
  ;;
exercise-updater)
  timeout 15m nix run .#update-pins -- --force --check difit
  git diff --exit-code
  checkout_status="$(git status --short)"
  test -z "$checkout_status"
  ;;
verify-original)
  git -C "$GITHUB_WORKSPACE" diff --exit-code
  original_status="$(git -C "$GITHUB_WORKSPACE" status --short)"
  test -z "$original_status"
  ;;
*)
  printf 'usage: %s {build-private|live-upstream|create-checkout|exercise-updater|verify-original}\n' "$0" >&2
  exit 2
  ;;
esac
