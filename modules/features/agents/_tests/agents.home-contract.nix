{
  inputs,
  lib,
}:
let
  expectedSkills = [
    "agent-browser"
    "agent-slack"
    "ast-grep"
    "ax"
    "commit"
    "difit"
    "difit-review"
    "drawio"
    "frontend-design"
    "hunk-review"
    "improve"
    "japanese-tech-writing"
    "missing-tools"
    "pptx"
  ];
in
{
  describe =
    target:
    let
      inherit (target) config pkgs;
      packages = config.home.packages;
      packageNames = map lib.getName packages;
      platform = config.dotfiles.platform;
      commandPolicy = config.dotfiles.agentCommandPolicyCompiled;
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
      environment = {
        inherit (platform) environment source;
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
        agents = skillNamesFor ".agents/skills/";
        claude = skillNamesFor ".claude/skills/";
      };
      policy = {
        schemaVersion = commandPolicy.guardPolicy.schemaVersion;
        allowsAx = lib.any (rule: rule.argvPrefix == [ "ax" ]) commandPolicy.prefixRules;
        allowsGitWrites =
          lib.all (prefix: lib.any (rule: rule.argvPrefix == prefix) commandPolicy.prefixRules)
            [
              [
                "git"
                "clone"
              ]
              [
                "git"
                "commit"
              ]
            ];
        allowsGhRepositoryAccess =
          lib.all (prefix: lib.any (rule: rule.argvPrefix == prefix) commandPolicy.prefixRules)
            [
              [
                "gh"
                "api-get"
              ]
              [
                "gh"
                "repo"
                "read-file"
              ]
            ];
        allowsRg = lib.any (rule: rule.argvPrefix == [ "rg" ]) commandPolicy.prefixRules;
        deniesTrashEmpty = lib.any (
          rule: rule.argvPrefix == [ "trash-empty" ] && rule.decision == "deny"
        ) commandPolicy.guardPolicy.exact;
        guardsSemanticCommands =
          lib.all (prefix: lib.any (rule: rule.commandPrefix == prefix) commandPolicy.guardPolicy.semantic)
            [
              [ "fd" ]
              [ "rm" ]
              [ "trash-restore" ]
            ];
        inherit (commandPolicy.guardPolicy.unknown)
          dynamicExecutable
          dynamicRelevantOption
          parseError
          ;
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
    environment = {
      inherit (facts) environment;
      source = facts.registryPath;
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
      agents = expectedSkills;
      claude = expectedSkills;
    };
    policy = {
      schemaVersion = 2;
      allowsAx = true;
      allowsGitWrites = true;
      allowsGhRepositoryAccess = true;
      allowsRg = true;
      deniesTrashEmpty = true;
      guardsSemanticCommands = true;
      dynamicExecutable = "deny";
      dynamicRelevantOption = "deny";
      parseError = "deny";
    };
    activation = {
      claudeBeforeCheckLinkTargets = true;
      claudeHandlesDanglingLegacyTarget = true;
      codexAfterLinkGeneration = true;
    };
    hunkUsesPlatformRuntime = true;
  };
}
