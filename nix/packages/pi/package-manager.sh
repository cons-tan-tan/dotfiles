pi_npm_home="${PI_NPM_HOME:-$HOME/.pi/npm-env}"
export PNPM_HOME="$pi_npm_home/pnpm-home"
export XDG_CACHE_HOME="$pi_npm_home/cache"
export XDG_DATA_HOME="$pi_npm_home/data"
export XDG_STATE_HOME="$pi_npm_home/state"
export NPM_CONFIG_USERCONFIG="$pi_npm_home/npmrc"
export NPM_CONFIG_GLOBALCONFIG="$pi_npm_home/global-npmrc"
export NPM_CONFIG_FUND=false
export NPM_CONFIG_AUDIT=false

mkdir -p \
  "$PNPM_HOME" \
  "$XDG_CACHE_HOME" \
  "$XDG_DATA_HOME" \
  "$XDG_STATE_HOME" \
  "$(dirname "$NPM_CONFIG_USERCONFIG")" \
  "$(dirname "$NPM_CONFIG_GLOBALCONFIG")"
touch "$NPM_CONFIG_USERCONFIG" "$NPM_CONFIG_GLOBALCONFIG"

export PATH="$NODE_BIN:$PNPM_HOME:$PATH"
exec "$PNPM_BIN" "$@"
