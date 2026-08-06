#!/usr/bin/env bash

set -euo pipefail

if [[ $FLAKE_EVAL_RESULT != success ]]; then
  printf 'flake evaluation failed: %s\n' "$FLAKE_EVAL_RESULT" >&2
  exit 1
fi
if [[ $LINUX_RESULT != success ]]; then
  printf 'Linux lane failed: %s\n' "$LINUX_RESULT" >&2
  exit 1
fi
if [[ $DARWIN_RESULT != success ]]; then
  printf 'Darwin lane failed: %s\n' "$DARWIN_RESULT" >&2
  exit 1
fi
