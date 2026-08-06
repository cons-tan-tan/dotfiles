{
  inputs,
  lib,
}:
{
  describe =
    target:
    let
      inherit (target) config pkgs;
      packages = config.home.packages;
      packageNames = map lib.getName packages;
      platform = config.dotfiles.platform;
      claudeActivation = config.home.activation.claudeHooksDirectoryMigration;
      codexActivation = config.home.activation.codexHooksConfig;
      skillNamesFor =
        prefix:
        map (lib.removePrefix prefix) (
          builtins.filter (lib.hasPrefix prefix) (builtins.attrNames config.home.file)
        );
      countPackage =
        package: builtins.length (builtins.filter (candidate: candidate == package) packages);
    in
    {
      integrations = {
        hcomAbsent = config.dotfiles.agentIntegrations.hcom == null;
      };
      programs = {
        claude = config.programs.claude-code.enable;
        hunk = config.programs.hunk.enable;
        opencode = config.programs.opencode.enable;
      };
      packages = {
        claude = builtins.elem "claude-code" packageNames;
        codex = builtins.elem "codex-wrapped" packageNames;
        codexApp = builtins.length (builtins.filter (name: name == "codex-app") packageNames);
        herdr = builtins.elem "herdr" packageNames;
        hunk = builtins.elem config.programs.hunk.package packages;
        pi = builtins.elem "pi" packageNames;
        ax = countPackage inputs.ax.packages.${pkgs.stdenv.hostPlatform.system}.ax;
        ccusage = countPackage pkgs.ccusage;
        copilot = countPackage pkgs.github-copilot-cli;
        gemini = countPackage pkgs.gemini-cli;
        browser = countPackage pkgs.dotfilesPackages.agent-browser;
        slack = countPackage pkgs.dotfilesPackages.agent-slack;
        difit = countPackage pkgs.dotfilesPackages.difit;
        shellfirm = countPackage pkgs.dotfilesPackages.shellfirm;
      };
      files = {
        claudeSettings = config.home.file ? ".claude/settings.json";
        codexHooks = config.home.file ? ".codex/hooks.json";
        guidance = config.home.file ? ".agents/context";
        herdr = config.home.file ? ".config/herdr/config.toml";
        opencode = config.home.file ? ".config/opencode/plugins/herdr-agent-state.js";
        pi = config.home.file ? ".pi/agent/settings.json";
      };
      skills = {
        synchronized = skillNamesFor ".agents/skills/" == skillNamesFor ".claude/skills/";
        nonEmpty = skillNamesFor ".agents/skills/" != [ ];
      };
      activation = {
        claudeBeforeCheckLinkTargets = claudeActivation.before == [ "checkLinkTargets" ];
        claudeHandlesDanglingLegacyTarget =
          lib.hasInfix "realpath -m" claudeActivation.data
          && lib.hasInfix "$oldGenPath/home-files/.claude/hooks" claudeActivation.data
          && !lib.hasInfix "readlink -f" claudeActivation.data;
        codexAfterLinkGeneration = codexActivation.after == [ "linkGeneration" ];
      };
      hunkUsesPlatformRuntime =
        config.programs.hunk.package == (
          if platform.environment == "wsl" then
            pkgs.dotfilesPackages.hunk.wslRuntime
          else
            pkgs.dotfilesPackages.hunk.package
        );
    };
  expected = facts: {
    integrations = {
      hcomAbsent = true;
    };
    programs = {
      claude = true;
      hunk = true;
      opencode = true;
    };
    packages = {
      claude = true;
      codex = true;
      codexApp = if facts.environment == "darwin" then 1 else 0;
      herdr = true;
      hunk = true;
      pi = true;
      ax = 1;
      ccusage = 1;
      copilot = 1;
      gemini = 1;
      browser = 1;
      slack = 1;
      difit = 1;
      shellfirm = 1;
    };
    files = {
      claudeSettings = true;
      codexHooks = true;
      guidance = true;
      herdr = true;
      opencode = true;
      pi = true;
    };
    skills = {
      synchronized = true;
      nonEmpty = true;
    };
    activation = {
      claudeBeforeCheckLinkTargets = true;
      claudeHandlesDanglingLegacyTarget = true;
      codexAfterLinkGeneration = true;
    };
    hunkUsesPlatformRuntime = true;
  };
}
