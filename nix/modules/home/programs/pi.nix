{
  config,
  pkgs,
  lib,
  dotfilesDir,
  ...
}:
let
  piAgentDir = "${config.home.homeDirectory}/.pi/agent";
  settingsPath = "${piAgentDir}/settings.json";

  # Keep Pi's package-manager npm isolated from the user's normal Node/npm setup.
  # Pi-managed packages still install into ~/.pi/agent/npm or project .pi/npm;
  # this wrapper only controls the npm binary, cache, and npm config files.
  piNpm = pkgs.writeShellScript "pi-npm" ''
    set -euo pipefail

    pi_npm_home="''${PI_NPM_HOME:-$HOME/.pi/npm-env}"
    export NPM_CONFIG_PREFIX="$pi_npm_home/prefix"
    export NPM_CONFIG_CACHE="$pi_npm_home/cache"
    export NPM_CONFIG_USERCONFIG="$pi_npm_home/npmrc"
    export NPM_CONFIG_GLOBALCONFIG="$pi_npm_home/global-npmrc"
    export NPM_CONFIG_FUND=false
    export NPM_CONFIG_AUDIT=false

    mkdir -p \
      "$NPM_CONFIG_PREFIX" \
      "$NPM_CONFIG_CACHE" \
      "$(dirname "$NPM_CONFIG_USERCONFIG")" \
      "$(dirname "$NPM_CONFIG_GLOBALCONFIG")"
    touch "$NPM_CONFIG_USERCONFIG" "$NPM_CONFIG_GLOBALCONFIG"

    export PATH="${pkgs.nodejs}/bin:$PATH"
    exec ${pkgs.nodejs}/bin/npm "$@"
  '';

  managedSettings = {
    # Force Pi's package manager to use the isolated wrapper above even when
    # node/npm are available in the user's interactive PATH.
    npmCommand = [ piNpm ];

    enableInstallTelemetry = false;
  };
  managedSettingsJson = (pkgs.formats.json { }).generate "pi-managed-settings.json" managedSettings;
in
{
  home.sessionVariables = {
    PI_SKIP_VERSION_CHECK = "1";
    PI_TELEMETRY = "0";
  };

  home.file.".pi/agent/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/claude/CLAUDE.md";

  # Keep settings mutable for Pi-owned fields, but make selected keys
  # declarative. Project .pi/settings.json can still add packages and resources.
  home.activation.piSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    settings="${settingsPath}"
    desired="${managedSettingsJson}"
    run mkdir -p "$(dirname "$settings")"
    if [ -f "$settings" ]; then
      run ${pkgs.bash}/bin/bash -euo pipefail -c ${lib.escapeShellArg ''
        settings="$1"
        desired="$2"
        candidate=$(${pkgs.coreutils}/bin/mktemp "$settings.nix-XXXXXX")
        trap '${pkgs.coreutils}/bin/rm -f "$candidate"' EXIT
        ${pkgs.jq}/bin/jq -s '.[0] * .[1]' "$settings" "$desired" > "$candidate"
        ${pkgs.coreutils}/bin/mv -f "$candidate" "$settings"
      ''} _ "$settings" "$desired"
    else
      run ${pkgs.coreutils}/bin/cp "$desired" "$settings"
    fi
  '';
}
