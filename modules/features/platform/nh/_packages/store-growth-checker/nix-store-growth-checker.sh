# shellcheck shell=bash

set -euo pipefail

original_arguments=("$@")

usage() {
  cat >&2 <<'EOF'
usage:
  nix-store-growth-checker check --state-directory PATH --store-path PATH --growth-threshold-bytes BYTES --maximum-age-seconds SECONDS --retry-interval-seconds SECONDS
  nix-store-growth-checker record --state-directory PATH --store-path PATH
EOF
  exit 2
}

is_uint63() {
  local value=$1
  local maximum=9223372036854775807

  [[ $value =~ ^(0|[1-9][0-9]*)$ ]] || return 1
  ((${#value} < ${#maximum})) && return 0
  ((${#value} == ${#maximum})) || return 1
  # Equal-length canonical decimals preserve numeric order lexicographically.
  # shellcheck disable=SC2071
  [[ $value < $maximum || $value == "$maximum" ]]
}

is_positive_uint63() {
  [[ $1 != 0 ]] && is_uint63 "$1"
}

command=${1:-}
[[ -n $command ]] || usage
shift

state_directory=
store_path=
growth_threshold_bytes=
maximum_age_seconds=
retry_interval_seconds=

while (($# > 0)); do
  case "$1" in
  --state-directory)
    (($# >= 2)) || usage
    state_directory=$2
    shift 2
    ;;
  --store-path)
    (($# >= 2)) || usage
    store_path=$2
    shift 2
    ;;
  --growth-threshold-bytes)
    (($# >= 2)) || usage
    growth_threshold_bytes=$2
    shift 2
    ;;
  --maximum-age-seconds)
    (($# >= 2)) || usage
    maximum_age_seconds=$2
    shift 2
    ;;
  --retry-interval-seconds)
    (($# >= 2)) || usage
    retry_interval_seconds=$2
    shift 2
    ;;
  *)
    echo "unknown argument: $1" >&2
    usage
    ;;
  esac
done

case "$command" in
check | record) ;;
*)
  echo "unknown command: $command" >&2
  usage
  ;;
esac

if [[ $state_directory != /* ]]; then
  echo "--state-directory must be an absolute path" >&2
  exit 2
fi
if [[ $store_path != /* || ! -d $store_path ]]; then
  echo "--store-path must name an existing absolute directory" >&2
  exit 2
fi
if [[ $command == check ]] && ! is_positive_uint63 "$growth_threshold_bytes"; then
  echo "--growth-threshold-bytes must be a positive integer for check" >&2
  exit 2
fi
if [[ $command == check ]] && ! is_positive_uint63 "$maximum_age_seconds"; then
  echo "--maximum-age-seconds must be a positive integer for check" >&2
  exit 2
fi
if [[ $command == check ]] && ! is_positive_uint63 "$retry_interval_seconds"; then
  echo "--retry-interval-seconds must be a positive integer for check" >&2
  exit 2
fi
if [[ $command == record && (-n $growth_threshold_bytes || -n $maximum_age_seconds || -n $retry_interval_seconds) ]]; then
  echo "growth, maximum age, and retry options are only valid for check" >&2
  exit 2
fi

umask 0027
install -d -m 0750 -- "$state_directory"

state_file=$state_directory/state
lock_file=$state_directory/lock

# Perl's flock is backed by the same advisory locking primitive on Linux and
# Darwin. The descriptor remains open across exec, so concurrent check/record
# processes serialize and a crash releases the lock without stale files.
if [[ ${NIX_STORE_GROWTH_LOCK_HELD:-false} != true ]]; then
  export NIX_STORE_GROWTH_LOCK_HELD=true
  exec perl -MFcntl=:flock,F_SETFD -e '
    use strict;
    use warnings;
    my $lock_path = shift @ARGV;
    open my $lock, ">>", $lock_path or die "cannot open lock $lock_path: $!\n";
    flock($lock, LOCK_EX) or die "cannot lock $lock_path: $!\n";
    fcntl($lock, F_SETFD, 0) or die "cannot inherit lock $lock_path: $!\n";
    exec { $ARGV[0] } @ARGV or die "cannot exec $ARGV[0]: $!\n";
  ' "$lock_file" "$BASH" "$0" "${original_arguments[@]}"
fi

store_mtime() {
  stat --printf '%y\n' -- "$store_path"
}

store_nar_bytes() {
  local json_format_arguments=()

  if [[ ${NIX_STORE_GROWTH_JSON_FORMAT_1:-false} == true ]]; then
    json_format_arguments=(--json-format 1)
  fi
  "${NIX_STORE_GROWTH_NIX:-nix}" path-info --store daemon --json \
    "${json_format_arguments[@]}" --all |
    jq --exit-status --raw-output '
    if type != "object" then
      error("nix path-info did not return an object")
    elif all(.[]; (.narSize | type) == "number" and .narSize >= 0) then
      [.[] | .narSize] | add // 0
    else
      error("nix path-info returned an invalid narSize")
    end
  '
}

write_state() {
  local baseline_bytes=$1
  local observed_mtime=$2
  local last_success_epoch=$3
  local last_trigger_epoch=$4
  local temporary

  temporary=$(mktemp "$state_directory/.state.XXXXXX")
  printf '2\t%s\t%s\t%s\t%s\n' \
    "$baseline_bytes" "$observed_mtime" "$last_success_epoch" "$last_trigger_epoch" >"$temporary"
  chmod 0640 "$temporary"
  mv -- "$temporary" "$state_file"
}

read_state() {
  local version extra

  [[ -f $state_file ]] || return 1
  version=
  baseline_bytes=
  previous_mtime=
  last_success_epoch=
  last_trigger_epoch=
  extra=
  IFS=$'\t' read -r version baseline_bytes previous_mtime last_success_epoch last_trigger_epoch extra \
    <"$state_file" || true
  [[ $version == 2 && -n $previous_mtime && -z $extra ]] &&
    is_uint63 "$baseline_bytes" && is_uint63 "$last_success_epoch" &&
    is_uint63 "$last_trigger_epoch"
}

record_baseline() {
  local last_success_epoch=$1
  local last_trigger_epoch=$2
  local message=$3
  local observed_mtime current_bytes

  # Capture mtime before enumeration. A store mutation during enumeration then
  # remains visible to the next check instead of being hidden by this record.
  observed_mtime=$(store_mtime)
  current_bytes=$(store_nar_bytes)
  is_uint63 "$current_bytes" || {
    echo "invalid Nix store NAR size: $current_bytes" >&2
    exit 2
  }

  write_state "$current_bytes" "$observed_mtime" "$last_success_epoch" "$last_trigger_epoch"
  printf '%s: %s bytes\n' "$message" "$current_bytes"
}

if [[ $command == record ]]; then
  record_baseline "$(date +%s)" 0 "recorded Nix store baseline"
  exit 0
fi

if [[ ! -e $state_file ]]; then
  record_baseline 0 "$(date +%s)" "initialized Nix store baseline"
  exit 0
fi

if ! read_state; then
  corrupt_state=$state_file.corrupt-$(date +%s)-$$
  mv -- "$state_file" "$corrupt_state"
  echo "moved invalid Nix store growth state to $corrupt_state" >&2
  record_baseline 0 "$(date +%s)" "reinitialized Nix store baseline"
  exit 0
fi

now_epoch=$(date +%s)
if ((last_success_epoch > now_epoch)); then
  # A clock correction must not postpone the safety cleanup indefinitely.
  last_success_epoch=0
fi
if ((last_trigger_epoch > now_epoch)); then
  last_trigger_epoch=0
fi

if ((last_trigger_epoch > 0 && now_epoch - last_trigger_epoch < retry_interval_seconds)); then
  printf 'Nix store cleanup retry is cooling down\n'
  exit 1
fi

if ((last_success_epoch == 0 || now_epoch - last_success_epoch >= maximum_age_seconds)); then
  write_state "$baseline_bytes" "$previous_mtime" "$last_success_epoch" "$now_epoch"
  printf 'Nix store cleanup maximum age reached: %s seconds (maximum: %s seconds)\n' \
    "$((now_epoch - last_success_epoch))" "$maximum_age_seconds"
  exit 0
fi

observed_mtime=$(store_mtime)
if [[ $observed_mtime == "$previous_mtime" ]]; then
  exit 1
fi

current_bytes=$(store_nar_bytes)
is_uint63 "$current_bytes" || {
  echo "invalid Nix store NAR size: $current_bytes" >&2
  exit 2
}

if ((current_bytes < baseline_bytes)); then
  # Accommodate a manual or externally initiated GC without repeatedly
  # comparing against a stale high-water mark.
  write_state "$current_bytes" "$observed_mtime" "$last_success_epoch" 0
  printf 'reset Nix store baseline after shrink: %s bytes\n' "$current_bytes"
  exit 1
fi

growth_bytes=$((current_bytes - baseline_bytes))
if ((growth_bytes >= growth_threshold_bytes)); then
  # Preserve the previously acknowledged mtime so a failed cleanup remains
  # eligible for retry after the cooldown even if the store does not mutate.
  write_state "$baseline_bytes" "$previous_mtime" "$last_success_epoch" "$now_epoch"
  printf 'Nix store growth threshold reached: %s bytes (threshold: %s bytes)\n' \
    "$growth_bytes" "$growth_threshold_bytes"
  exit 0
fi

write_state "$baseline_bytes" "$observed_mtime" "$last_success_epoch" 0
printf 'Nix store growth below threshold: %s bytes (threshold: %s bytes)\n' \
  "$growth_bytes" "$growth_threshold_bytes"
exit 1
