{
  inputs,
  ...
}:
{
  features.agent-claude.homeManager =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      platform = config.dotfiles.platform;
      dotfilesDir = platform.source;
      hcom = config.dotfiles.agentIntegrations.hcom;
      payload = import ./_interface/payload.nix;

      claudeHome = "${config.home.homeDirectory}/.claude";
      herdrClaudeIntegration = pkgs.dotfilesPackages.herdr.integrations.claude;
      herdrHookPath = "${claudeHome}/hooks/herdr-agent-state.sh";
      herdrSettings = import ../herdr/_interface/session-hook.nix {
        inherit lib pkgs;
      };
      herdrHookCommand = herdrSettings.mkSessionHookCommand herdrHookPath;

      commandPolicy = config.dotfiles.agentCommandPolicyCompiled;
      settingsLib = import ./_interface/settings.nix {
        inherit lib commandPolicy;
      };
      settingsValidator = import ./_interface/settings-validator.nix {
        inherit pkgs;
        schemaPin = import ./_interface/settings-schema.nix;
      };
      agentPackageSources = import ../base/_interface/package-sources.nix;
      commandPolicyInterface = import ../base/_interface/command-policy.nix;
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
      migrateHooksDirectory = pkgs.writeShellApplication {
        name = "migrate-claude-hooks-directory";
        runtimeInputs = [ pkgs.coreutils ];
        text = builtins.readFile ./_scripts/migrate-hooks-directory.sh;
      };
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
        run ${pkgs.coreutils}/bin/env \
          CLAUDE_HOME=${lib.escapeShellArg claudeHome} \
          DOTFILES_DIR=${lib.escapeShellArg dotfilesDir} \
          OLD_GEN_PATH="''${oldGenPath-}" \
          ${lib.getExe migrateHooksDirectory}
      '';
    };
}
