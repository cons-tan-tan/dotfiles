usage() {
  cat >&2 <<'EOF'
Usage:
  nh-clean-growth-runner check STATE_DIRECTORY
  nh-clean-growth-runner record STATE_DIRECTORY
EOF
  exit 2
}

if (($# != 2)); then
  usage
fi

action=$1
state_directory=$2

if [[ $state_directory != /* ]]; then
  echo "STATE_DIRECTORY must be an absolute path" >&2
  exit 2
fi

case $action in
check)
  if timeout --signal=TERM --kill-after=30s "$query_timeout" \
    "$growth_checker" check \
    --state-directory "$state_directory" \
    --store-path "$store_path" \
    --growth-threshold-bytes "$threshold_bytes" \
    --maximum-age-seconds "$maximum_age_seconds" \
    --retry-interval-seconds "$retry_interval_seconds"; then
    "${cleanup_command[@]}"
    exec timeout --signal=TERM --kill-after=30s "$query_timeout" \
      "$growth_checker" record \
      --state-directory "$state_directory" \
      --store-path "$store_path"
  else
    status=$?
    # A status of one is the checker's normal "cleanup not needed" result.
    ((status == 1)) && exit 0
    exit "$status"
  fi
  ;;
record)
  exec timeout --signal=TERM --kill-after=30s "$query_timeout" \
    "$growth_checker" record \
    --state-directory "$state_directory" \
    --store-path "$store_path"
  ;;
*)
  echo "unknown action: $action" >&2
  usage
  ;;
esac
