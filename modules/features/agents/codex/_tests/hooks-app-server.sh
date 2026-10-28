if [[ ${CODEX_HOOKS_TEST_FAIL:-} == 1 ]]; then
  echo "fixture hook inspection failure" >&2
  exit 23
fi

# Check the child-process boundary, including inherited environment overrides.
[[ $# == 3 && $1 == app-server && $2 == --listen && $3 == stdio:// ]]
[[ ! -v CODEX_HOME ]]
[[ $PWD == "$HOME" ]]
[[ $XDG_CONFIG_HOME == "$HOME/.config" ]]
[[ $(cat "$HOME/.codex/config.toml") == $'[features]\nhooks = true' ]]
[[ ! -L $HOME/.codex/hooks.json ]]
[[ $(stat -c %a "$HOME/.codex/hooks.json") == 600 ]]

read -r request
jq -e '.method == "initialize" and .id == 1' <<<"$request" >/dev/null
printf '{"id":1,"result":{}}\n'
read -r request
jq -e '.method == "initialized"' <<<"$request" >/dev/null
read -r request
jq -e --arg cwd "$HOME" \
  '.method == "hooks/list" and .id == 2 and .params.cwds == [$cwd]' <<<"$request" >/dev/null
jq -nc --arg path "$HOME/.codex/hooks.json" \
  --slurpfile source "$HOME/.codex/hooks.json" '{
    id: 2,
    result: {data: [{hooks: [{
      key: ($path + ":session_start:0:0"),
      eventName: "sessionStart",
      handlerType: "command",
      matcher: null,
      command: $source[0].hooks.SessionStart[0].hooks[0].command,
      timeoutSec: $source[0].hooks.SessionStart[0].hooks[0].timeout,
      enabled: true,
      currentHash: "sha256:fixture"
    }]}]}
  }'
