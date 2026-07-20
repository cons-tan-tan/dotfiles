set -euo pipefail

reject() {
  echo "gh-api-get: '$1' is not allowed; this wrapper always appends --method GET" >&2
  exit 2
}

for arg in "$@"; do
  case "$arg" in
  -- | --method | --method=* | -X | -X*)
    reject "$arg"
    ;;
  esac
done

exec gh api "$@" --method GET
