# curl の GET 専用ラッパー。エージェントの自動許可前提なので、用途を
# 取得系の小さなフラグ集合に閉じ込めて監査可能にする。
# nix/modules/home/programs/curl.nix が writeShellApplication で包む。
set -euo pipefail

ATFILE_ERR="Error: '@file' syntax is not allowed in header values"

LONG_NO_VALUE_FLAGS=(
  --silent
  --show-error
  --location
  --fail
  --fail-with-body
  --compressed
  --no-progress-meter
  --ipv4
  --ipv6
)

LONG_VALUE_FLAGS=(
  --user-agent
  --header
  --max-time
  --connect-timeout
  --retry
  --retry-delay
  --retry-max-time
  --url
)

pending_option=""

contains() {
  local needle=$1
  shift
  local item
  for item in "$@"; do
    if [[ $needle == "$item" ]]; then
      return 0
    fi
  done
  return 1
}

reject_option() {
  echo "Error: '$1' is not allowed" >&2
  exit 1
}

check_url() {
  local value=$1
  case "$value" in
  http://* | https://*)
    ;;
  *)
    echo "Error: URL '$value' must use http:// or https://" >&2
    exit 1
    ;;
  esac
}

check_value() {
  local option=$1
  local value=$2
  if [[ $option == "-H" || $option == "--header" ]] && [[ $value == @* ]]; then
    echo "$ATFILE_ERR" >&2
    exit 1
  fi
  if [[ $option == "--url" ]]; then
    check_url "$value"
  fi
}

parse_long_option() {
  local arg=$1
  local flag=${arg%%=*}
  local value

  if contains "$flag" "${LONG_NO_VALUE_FLAGS[@]}"; then
    if [[ $arg == *=* ]]; then
      reject_option "$flag"
    fi
    return 0
  fi

  if contains "$flag" "${LONG_VALUE_FLAGS[@]}"; then
    if [[ $arg == *=* ]]; then
      value=${arg#*=}
      check_value "$flag" "$value"
    else
      pending_option=$flag
    fi
    return 0
  fi

  reject_option "$flag"
}

parse_short_option() {
  local arg=$1
  local chars=${arg#-}
  local c rest

  if [[ -z $chars ]]; then
    reject_option "$arg"
  fi

  for ((i = 0; i < ${#chars}; i++)); do
    c=${chars:i:1}
    case "$c" in
    s | S | L | f)
      ;;
    A | H | m)
      rest=${chars:$((i + 1))}
      if [[ -n $rest ]]; then
        check_value "-$c" "$rest"
      else
        pending_option="-$c"
      fi
      return 0
      ;;
    *)
      reject_option "-$c"
      ;;
    esac
  done
}

for arg in "$@"; do
  if [[ -n $pending_option ]]; then
    check_value "$pending_option" "$arg"
    pending_option=""
    continue
  fi

  if [[ $arg == "--" ]]; then
    echo "Error: '--' is not allowed" >&2
    exit 1
  fi

  if [[ $arg == --* ]]; then
    parse_long_option "$arg"
    continue
  fi

  if [[ $arg == -* ]]; then
    parse_short_option "$arg"
    continue
  fi

  check_url "$arg"
done

if [[ -n $pending_option ]]; then
  echo "Error: '$pending_option' requires a value" >&2
  exit 1
fi

# -q: .curlrc の自動読み込みを無効化し、設定ファイル経由のフラグ注入を防止
exec curl -q --proto '=http,https' --proto-redir '=http,https' "$@"
