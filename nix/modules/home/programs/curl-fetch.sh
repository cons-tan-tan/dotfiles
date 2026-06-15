# curl の read-only HTTP(S) ラッパー。エージェントの自動許可前提なので、
# 用途を取得系の小さなフラグ集合に閉じ込めて監査可能にする。
# nix/modules/home/programs/curl.nix が writeShellApplication で包む。
set -euo pipefail

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
  --head
  --show-headers
  --globoff
)

LONG_VALUE_FLAGS=(
  --user-agent
  --header
  --max-time
  --connect-timeout
  --retry
  --retry-delay
  --retry-max-time
  --max-redirs
  --range
  --url
  --output
  --write-out
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
  local option=$1
  local reason="it is not on curl-fetch's small read-only allowlist."
  local alternative="Use WebFetch/agent-browser, raw curl with explicit approval, or add this option to the allowlist after reviewing its side effects."

  case "$option" in
  -X | --request | --request-target | -d | --data* | -F | --form | --form-string | -T | --upload-file | --json | --post301 | --post302 | --post303)
    reason="it can change the request away from a read-only fetch."
    alternative="Use raw curl with explicit approval, or gh api/gh api-get for GitHub API requests."
    ;;
  -O | --remote-name | --remote-name-all | -J | --remote-header-name | --output-dir | --create-dirs | --create-file-mode | --no-clobber | --skip-existing | --remove-on-error)
    reason="it lets curl derive or manage local output paths beyond an explicit output file."
    alternative="Use -o/--output with an explicit path, or shell redirection when file writes are appropriate."
    ;;
  -D | --dump-header)
    reason="it writes headers to a separate file through curl."
    alternative="Use -i/--show-headers to include headers on stdout, or -I/--head for headers only."
    ;;
  --stderr)
    reason="it redirects diagnostics to a file through curl."
    alternative="Use shell stderr redirection when file writes are appropriate."
    ;;
  --cookie-jar | --trace | --trace-ascii | --etag-save | --libcurl | --hsts | --alt-svc | --ssl-sessions | --xattr)
    reason="it creates or updates curl state, metadata, trace, or generated-code files."
    alternative="Use raw curl with explicit approval if that side effect is intentional."
    ;;
  -K | --config | -b | --cookie | --netrc | --netrc-file | --netrc-optional | --cacert | --capath | -E | --cert | --key | --random-file | --egd-file | --crlfile | --proxy-cacert | --proxy-capath | --proxy-cert | --proxy-key)
    reason="it can read local files or credentials into the request."
    alternative="Use raw curl with explicit approval when local credentials, cookies, or certificate files are required."
    ;;
  -k | --insecure | --proxy-insecure)
    reason="it weakens TLS verification."
    alternative="Use raw curl with explicit approval if an insecure endpoint must be inspected."
    ;;
  --proto | --proto-default | --proto-redir)
    reason="it can override curl-fetch's HTTP/HTTPS protocol restriction."
    alternative="curl-fetch already pins --proto and --proto-redir to http,https."
    ;;
  --location-trusted)
    reason="it can forward credentials to hosts reached through redirects."
    alternative="Use --location unless credential forwarding across redirects is explicitly required."
    ;;
  --next | -:)
    reason="it creates multiple transfer contexts with separate option state."
    alternative="Run separate curl-fetch commands so each fetch is independently auditable."
    ;;
  --proxy* | --preproxy | --socks* | --connect-to | --resolve | --doh-url | --interface | --unix-socket | --abstract-unix-socket)
    reason="it changes the network path or destination resolution."
    alternative="Use raw curl with explicit approval when custom proxying or host resolution is required."
    ;;
  esac

  echo "Error: '$option' is not allowed by curl-fetch." >&2
  echo "Reason: $reason" >&2
  echo "Alternative: $alternative" >&2
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
    echo "Error: '$option' does not allow @file values in curl-fetch." >&2
    echo "Reason: @file syntax reads a local file into the request." >&2
    echo "Alternative: Pass a literal header value, or use raw curl with explicit approval if reading a header from a file is intentional." >&2
    exit 1
  fi
  if [[ $option == "-w" || $option == "--write-out" ]] && [[ $value == @* ]]; then
    echo "Error: '$option' does not allow @file values in curl-fetch." >&2
    echo "Reason: @file syntax reads a local format string from disk." >&2
    echo "Alternative: Pass a literal write-out format, for example --write-out '%{http_code}'." >&2
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
    s | S | L | f | I | i | g)
      ;;
    A | H | m | o | w | r)
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
