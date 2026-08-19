set -euo pipefail

: "${TRASH_DIRECTORY:?}"

mkdir -p -- "$TRASH_DIRECTORY/files" "$TRASH_DIRECTORY/info"
chmod 0700 -- "$TRASH_DIRECTORY" "$TRASH_DIRECTORY/files" "$TRASH_DIRECTORY/info"
