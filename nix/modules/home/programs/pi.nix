{
  config,
  pkgs,
  ...
}:
let
  models = import ../../../lib/settings/models.nix;
  piFamily = pkgs.dotfilesPackages.pi;
  piPnpm = piFamily.packageManager;

  piPackages = [
    "npm:pi-skillrefs@0.1.3"
    "npm:pi-web-access@0.10.7"
  ];

  herdrSkillLoader = pkgs.replaceVars ../../../../pi/extensions/herdr-skill-loader.ts {
    herdrSkillPath = "${pkgs.dotfilesPackages.herdr.agent.plugin}/skills/herdr";
  };
  herdrPiIntegration = pkgs.dotfilesPackages.herdr.integrations.pi;

  managedSettings = {
    defaultProvider = models.pi.provider;
    defaultModel = models.pi.model;
    defaultThinkingLevel = models.pi.thinkingLevel;

    # Force Pi's package manager to use the isolated wrapper above even when
    # node/npm/pnpm are available in the user's interactive PATH.
    npmCommand = [ "${piPnpm}/bin/pnpm" ];

    extensions = [ "~/.pi/agent/extensions" ];

    packages = piPackages;

    enableInstallTelemetry = false;
  };
  # Unlike Claude/Codex, Pi currently does not provide a settings JSON Schema
  # we can validate against. Investigated on 2026-07-06: Pi 0.79.1 package
  # tree, dist/core/settings-manager.d.ts, docs/settings.md, and the upstream
  # earendil-works/pi file tree expose settings types/docs but no schema.
  managedSettingsJson = (pkgs.formats.json { }).generate "pi-managed-settings.json" managedSettings;

  packageDir = "${config.home.homeDirectory}/.pi/agent/package";
  pi = piFamily.mkWrappedPackage {
    inherit packageDir;
  };
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
