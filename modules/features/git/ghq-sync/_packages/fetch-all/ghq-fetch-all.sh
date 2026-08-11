ghq list -p |
  xargs -r -d '\n' -P8 -I{} sh -c '
      if ! timeout 60s git -C "$1" fetch --all --prune --quiet 2>&1; then
        echo "WARN: fetch failed for $1" >&2
      fi
    ' _ {}
