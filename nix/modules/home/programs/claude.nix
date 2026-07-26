{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
let
  inherit (config.my) dotfilesDir;
  enableHcom = config.dotfiles.hcom.enable;

  claudeHome = "${config.home.homeDirectory}/.claude";
  herdrClaudeIntegration = pkgs.dotfilesPackages.herdr.integrations.claude;
  herdrHookPath = "${claudeHome}/hooks/herdr-agent-state.sh";
  herdrSettings = import ../../../lib/settings/herdr.nix { inherit lib pkgs; };
  herdrHookCommand = herdrSettings.mkSessionHookCommand herdrHookPath;

  settingsLib = import ../../../lib/settings/claude.nix { inherit lib; };
  settingsValidator = import ../../../lib/mk-claude-settings-validator.nix { inherit pkgs; };
  agentConfigHelper = pkgs.callPackage ../../../libexec/agent-config-helper { };

  jsonFormat = pkgs.formats.json { };

  baseSettingsFile = jsonFormat.generate "claude-settings-base.json" (
    settingsLib.mkSettings {
      isDarwin = config.my.isDarwin;
      wslUserProfile = if config.my.isWsl then config.my.windows.homedir else null;
      hcomPath = if enableHcom then "${pkgs.dotfilesPackages.hcom.package}/bin/hcom" else null;
    }
  );

  hcomSettingsFile =
    if enableHcom then
      pkgs.dotfilesPackages.hcom.integrations.claudeHooks
    else
      jsonFormat.generate "claude-hcom-disabled.json" {
        hooks = { };
        permissions.allow = [ ];
      };

  herdrSettingsFile =
    pkgs.runCommand "claude-herdr-settings.json"
      {
        nativeBuildInputs = [ agentConfigHelper ];
      }
      ''
        ${lib.getExe agentConfigHelper} claude rewrite-session-command \
          --command ${lib.escapeShellArg herdrHookCommand} \
          ${herdrClaudeIntegration}/settings.json \
          > "$out"
      '';

  # hcom が有効な場合は package が生成した設定を使い、手書きで二重管理しない。
  mergedSettingsRaw =
    pkgs.runCommand "claude-settings.json"
      {
        nativeBuildInputs = [ agentConfigHelper ];
      }
      ''
        ${lib.getExe agentConfigHelper} claude merge-settings \
          --base ${baseSettingsFile} \
          --hcom ${hcomSettingsFile} \
          --herdr ${herdrSettingsFile} \
          > "$out"
      '';

  mergedSettingsFile = settingsValidator.validate "claude-settings.json" mergedSettingsRaw;
in
{
  programs.claude-code = {
    enable = true;
    package = pkgs.dotfilesPackages.claude-code.package;
    plugins = [
      "${inputs.codex-plugin-cc}/plugins/codex"
    ];
    # settings は指定しない: settings = { } なら HM モジュールは settings.json を
    # 書かないので、build 時マージ結果 (mergedSettingsFile) を home.file で置ける。
  };

  home.file.".claude/settings.json".source = mergedSettingsFile;

  home.file.".claude/CLAUDE.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/claude/CLAUDE.md";
  home.file.".claude/commands".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/claude/commands";
  home.file.".claude/rules".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/claude/rules";
  home.file.".claude/output-styles".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/claude/output-styles";
  home.file.".claude/hooks/.gitkeep".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/claude/hooks/.gitkeep";
  home.file.".claude/hooks/herdr-agent-state.sh".source =
    "${herdrClaudeIntegration}/hooks/herdr-agent-state.sh";

  home.activation.claudeHooksDirectoryMigration = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    legacy_hooks="${claudeHome}/hooks"
    legacy_target="${dotfilesDir}/claude/hooks"
    if [ -L "$legacy_hooks" ] && [ "$(${pkgs.coreutils}/bin/readlink -f "$legacy_hooks")" = "$legacy_target" ]; then
      run ${pkgs.coreutils}/bin/rm "$legacy_hooks"
    fi
  '';
}
