{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
let
  platform = config.dotfiles.platform;
  dotfilesDir = platform.source;
  hcom = config.dotfiles.agentIntegrations.hcom;
  payload = import ../_interface/payload.nix;

  claudeHome = "${config.home.homeDirectory}/.claude";
  herdrClaudeIntegration = pkgs.dotfilesPackages.herdr.integrations.claude;
  herdrHookPath = "${claudeHome}/hooks/herdr-agent-state.sh";
  herdrSettings = import ../../herdr/_interface/session-hook.nix {
    inherit lib pkgs;
  };
  herdrHookCommand = herdrSettings.mkSessionHookCommand herdrHookPath;

  commandPolicy = config.dotfiles.agentCommandPolicyCompiled;
  settingsLib = import ./settings.nix {
    inherit lib commandPolicy;
  };
  settingsValidator = import ./settings-validator.nix {
    inherit pkgs;
  };
  agentPackageSources = import ../../base/_interface/package-sources.nix;
  commandPolicyInterface = import ../../base/_interface/command-policy.nix;
  agentConfigHelper = pkgs.callPackage agentPackageSources.configHelper { };
  guardHook = commandPolicyInterface.mkGuard {
    inherit lib pkgs;
    policy = commandPolicy.guardPolicy;
  };

  jsonFormat = pkgs.formats.json { };

  baseSettingsFile = jsonFormat.generate "claude-settings-base.json" (
    settingsLib.mkSettings {
      isDarwin = platform.environment == "darwin";
      wslUserProfile = if platform.environment == "wsl" then platform.windows.homedir else null;
      hcomPath = if hcom == null then null else "${hcom.package}/bin/hcom";
      guardCommand = guardHook.command;
    }
  );

  hcomSettingsFile =
    if hcom != null then
      hcom.claudeHooks
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

  home.file.".claude/commands".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/${payload.repositoryRelative.commands}";
  home.file.".claude/output-styles".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/${payload.repositoryRelative.outputStyles}";
  home.file.".claude/hooks/.gitkeep".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/${payload.repositoryRelative.hooks}/.gitkeep";
  home.file.".claude/hooks/herdr-agent-state.sh".source =
    "${herdrClaudeIntegration}/hooks/herdr-agent-state.sh";

  home.activation.claudeHooksDirectoryMigration = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    legacy_hooks="${claudeHome}/hooks"
    legacy_target="${dotfilesDir}/claude/hooks"
    if [ -L "$legacy_hooks" ]; then
      link_target="$(${pkgs.coreutils}/bin/readlink "$legacy_hooks")"
      case "$link_target" in
        /*) ;;
        *) link_target="$(${pkgs.coreutils}/bin/dirname "$legacy_hooks")/$link_target" ;;
      esac
      normalized_target="$(${pkgs.coreutils}/bin/realpath -m "$link_target")"
      normalized_legacy_target="$(${pkgs.coreutils}/bin/realpath -m "$legacy_target")"
      old_generation_hooks=
      if [[ -v oldGenPath ]] && [[ -e "$oldGenPath/home-files/.claude/hooks" || -L "$oldGenPath/home-files/.claude/hooks" ]]; then
        old_generation_hooks="$(${pkgs.coreutils}/bin/realpath -m "$oldGenPath/home-files/.claude/hooks")"
      fi
      if [ "$normalized_target" = "$normalized_legacy_target" ] \
        || { [ -n "$old_generation_hooks" ] && [ "$normalized_target" = "$old_generation_hooks" ]; }; then
        run ${pkgs.coreutils}/bin/rm "$legacy_hooks"
      fi
    fi
  '';
}
