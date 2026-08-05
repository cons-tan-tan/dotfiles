#!/usr/bin/env bash

set -euo pipefail

installables_input=${INSTALLABLES:-}
read -r -a installables <<<"$installables_input"
if ((${#installables[@]} == 0)); then
  echo "matrix group has no installables" >&2
  exit 1
fi

hashes="$(
  printf '%s\n' "${installables[@]}" |
    awk -F/ '{printf "%s%s", (NR > 1 ? "," : ""), substr($NF, 1, 32)}'
)"
import_log="$(mktemp)"
trap 'rm -f "$import_log"' EXIT
max_resolved_references=4
resolved_reference_count=0
resolved_references='|'
prefetch_succeeded=false
store_path_pattern='^/nix/store/[0-9abcdfghijklmnpqrsvwxyz]{32}-[A-Za-z0-9+._?=-]+$'

# Hestia v3のupstream-cache-filterは署名済み参照を/closureから外す一方、
# exportされた親pathのReferencesには残す。nix-store --importは外部参照を
# substituteしないため、報告されたstore pathだけを通常cacheから取得して
# 再試行する。Hestia側で解決されるまでのworkaroundなので、診断文の解析と
# 再試行を厳密かつ有限にし、失敗時は下のnix buildへ委ねる。
while true; do
  : >"$import_log"
  if curl -fsS "http://$HESTIA_LISTEN/closure/$hashes" |
    nix-store --import 2>"$import_log"; then
    cat "$import_log" >&2
    prefetch_succeeded=true
    break
  fi
  cat "$import_log" >&2

  missing_path="$(
    sed -nE "s#^error: path '(/nix/store/[^']+)' is not valid\$#\\1#p" \
      "$import_log" |
      tail -n 1
  )"
  already_resolved=false
  if [[ $resolved_references == *"|$missing_path|"* ]]; then
    already_resolved=true
  fi
  if [[ ! $missing_path =~ $store_path_pattern ]] ||
    [[ $missing_path == *.drv ]] ||
    [[ $already_resolved == true ]] ||
    ((resolved_reference_count >= max_resolved_references)); then
    break
  fi

  echo "Substituting filtered Hestia closure reference: $missing_path"
  if ! nix-store --realise "$missing_path"; then
    break
  fi
  resolved_references+="$missing_path|"
  resolved_reference_count=$((resolved_reference_count + 1))
done

if [[ $prefetch_succeeded != true ]]; then
  echo "::warning::Hestia closure prefetch failed; falling back to normal Nix substitution"
fi
nix build "${installables[@]}"
