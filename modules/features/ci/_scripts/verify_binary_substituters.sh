#!/usr/bin/env bash

set -euo pipefail

substituters="$(nix config show substituters)"
read -r -a public_substituters <<<"$NIX_EXTRA_SUBSTITUTERS"

for expected in \
  https://cache.nixos.org \
  "${public_substituters[@]}" \
  http://127.0.0.1:; do
  if [[ $substituters != *"$expected"* ]]; then
    echo "missing substituter: $expected" >&2
    echo "configured substituters: $substituters" >&2
    exit 1
  fi
done
