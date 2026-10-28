if [[ $# != 3 || ($2 != --state-generator && $2 != --payload) ]]; then
  echo "usage: codex-config-reconcile <config.toml> (--state-generator <executable> | --payload <json>)" >&2
  exit 2
fi

config_path=$1
# Keep the candidate on the target filesystem so replacement remains atomic.
workspace=$(mktemp -d "${config_path}.hooks-XXXXXX")
trap 'rm -rf -- "$workspace"' EXIT
candidate="$workspace/config.toml"

case "$2" in
--state-generator)
  "$3" >"$workspace/hooks-state.json"
  "$config_helper" codex merge-payloads \
    "$base_payload" "$workspace/hooks-state.json" >"$workspace/merge-payload.json"
  merge_payload="$workspace/merge-payload.json"
  ;;
--payload)
  merge_payload=$3
  ;;
esac

"$config_helper" merge "$config_path" "$merge_payload" "$candidate"
taplo check "$candidate"
taplo check --schema "file://$config_schema" "$candidate"
mv -f -- "$candidate" "$config_path"
