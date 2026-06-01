{
  config,
  pkgs,
  dotfilesDir,
  ...
}:
let
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

  packageDir = "${config.home.homeDirectory}/.pi/agent/package";
  pi = pkgs.writeShellScriptBin "pi" ''
    export PI_PACKAGE_DIR="${packageDir}"
    export PI_SKIP_VERSION_CHECK=1
    export PI_TELEMETRY=0

    exec ${pkgs.pi}/bin/pi "$@"
  '';
in
{
  home.packages = [ pi ];

  home.file.".pi/agent/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/claude/CLAUDE.md";

  home.file.".pi/agent/package".source =
    "${pkgs.pi}/lib/node_modules/@earendil-works/pi-coding-agent";

  # Global settings are declarative. Pi may try to persist UI choices, installs,
  # or extension configuration here; those writes should fail instead of
  # mutating global state outside Nix.
  home.file.".pi/agent/settings.json" = {
    source = managedSettingsJson;
    force = true;
  };
}
