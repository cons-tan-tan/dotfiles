#!/usr/bin/env bash

set -euo pipefail

if [[ $EVAL_RESULT != success ]]; then
  printf 'matrix evaluation failed: %s\n' "$EVAL_RESULT" >&2
  exit 1
fi

if [[ $ANY_JOBS == true ]]; then
  if [[ $BUILD_RESULT != success ]]; then
    printf 'matrix build failed: %s\n' "$BUILD_RESULT" >&2
    exit 1
  fi
elif [[ $ANY_JOBS == false ]]; then
  if [[ $BUILD_RESULT != skipped ]]; then
    printf 'unexpected empty matrix result: %s\n' "$BUILD_RESULT" >&2
    exit 1
  fi
else
  printf 'invalid any-jobs output: %s\n' "$ANY_JOBS" >&2
  exit 1
fi
