{ lib }:
{
  describe =
    target:
    let
      inherit (target) config;
      claude = config.home.activation.claudeHooksDirectoryMigration;
      claudeCode = config.programs.claude-code;
      codexPlugin = config.home.file."${claudeCode.configDir}/skills/codex";
      codex = config.home.activation.codexHooksConfig;
      dotfilesSource = builtins.unsafeDiscardStringContext (toString config.dotfiles.platform.source);
      oldGenExpansion = "$" + "{oldGenPath-}";
    in
    {
      claude = {
        usesConfiguredPackage = claudeCode.finalPackage == claudeCode.package;
        personalPlugin = {
          inherit (codexPlugin) target recursive;
        };
        before = claude.before;
        executable = lib.hasInfix "/bin/migrate-claude-hooks-directory" claude.data;
        claudeHome = lib.hasInfix "CLAUDE_HOME=${lib.escapeShellArg "${config.home.homeDirectory}/.claude"}" claude.data;
        dotfilesDir = lib.hasInfix "DOTFILES_DIR=${lib.escapeShellArg dotfilesSource}" claude.data;
        oldGeneration = lib.hasInfix "OLD_GEN_PATH=\"${oldGenExpansion}\"" claude.data;
      };
      codexAfter = codex.after;
    };
  expected = _: {
    claude = {
      usesConfiguredPackage = true;
      personalPlugin = {
        target = ".claude/skills/codex";
        recursive = false;
      };
      before = [ "checkLinkTargets" ];
      executable = true;
      claudeHome = true;
      dotfilesDir = true;
      oldGeneration = true;
    };
    codexAfter = [ "linkGeneration" ];
  };
}
