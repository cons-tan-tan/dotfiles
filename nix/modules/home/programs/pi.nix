{
  config,
  pkgs,
  ...
}:
let
  # Keep Pi's package-manager pnpm isolated from the user's normal Node/npm setup.
  # Pi-managed packages still install into ~/.pi/agent/npm or project .pi/npm;
  # this wrapper only controls the package-manager binary, cache, and configs.
  # The executable name must stay "pnpm"; Pi detects it to use pnpm-specific
  # install flags. home.packages には入れず npmCommand から絶対パスで参照する
  # だけなので、packages.nix の素の pnpm と PATH 上で衝突することはない。
  piPnpm = pkgs.writeShellScriptBin "pnpm" ''
    set -euo pipefail

    pi_npm_home="''${PI_NPM_HOME:-$HOME/.pi/npm-env}"
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

    export PATH="${pkgs.nodejs}/bin:$PNPM_HOME:$PATH"
    exec ${pkgs.pnpm}/bin/pnpm "$@"
  '';

  piPackages = [
    "npm:pi-skillrefs@0.1.3"
    "npm:pi-web-access@0.10.7"
  ];

  herdrSkillLoader = pkgs.replaceVars ../../../../pi/extensions/herdr-skill-loader.ts {
    herdrSkillPath = "${pkgs.herdr-agent-plugin}/skills/herdr";
  };
  herdrPiIntegration = pkgs.herdr-pi-integration;

  managedSettings = {
    defaultProvider = "openai-codex";
    defaultModel = "gpt-5.5";
    defaultThinkingLevel = "high";

    # Force Pi's package manager to use the isolated wrapper above even when
    # node/npm/pnpm are available in the user's interactive PATH.
    npmCommand = [ "${piPnpm}/bin/pnpm" ];

    extensions = [ "~/.pi/agent/extensions" ];

    packages = piPackages;

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
    config.lib.file.mkOutOfStoreSymlink "${config.my.dotfilesDir}/claude/CLAUDE.md";

  home.file.".pi/agent/package".source =
    "${pkgs.pi}/lib/node_modules/@earendil-works/pi-coding-agent";

  home.file.".pi/agent/extensions/herdr-skill-loader.ts".source = herdrSkillLoader;

  home.file.".pi/agent/extensions/herdr-agent-state.ts".source =
    "${herdrPiIntegration}/extensions/herdr-agent-state.ts";

  # Global settings are declarative. Pi may try to persist UI choices, installs,
  # or extension configuration here; those writes should fail instead of
  # mutating global state outside Nix. force は付けない: Pi が symlink を実
  # ファイルに置き換えた場合、黙って戻すより switch 時の衝突エラーで気付ける
  # 方が良い (リポジトリ方針として home.file の force = true は原則禁止)。
  home.file.".pi/agent/settings.json".source = managedSettingsJson;
}
