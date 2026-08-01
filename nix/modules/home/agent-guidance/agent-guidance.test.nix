{
  homeManager,
  lib,
  pkgs,
}:
let
  evaluated =
    (homeManager.lib.homeManagerConfiguration {
      inherit pkgs;
      modules = [
        ./default.nix
        {
          home = {
            username = "test";
            homeDirectory = "/home/test";
            stateVersion = "24.11";
          };
        }
      ];
    }).config;
  contextRoot = ../../../../agents/context;
  globalContext = contextRoot + "/global.md";
  rulesDirectory = contextRoot + "/rules";
  ruleEntries = builtins.readDir rulesDirectory;
  ruleNames = builtins.filter (name: ruleEntries.${name} == "regular" && lib.hasSuffix ".md" name) (
    builtins.attrNames ruleEntries
  );
  managedPaths = [
    ".agents/context"
    ".claude/CLAUDE.md"
    ".claude/rules"
    ".codex/AGENTS.md"
    ".pi/agent/AGENTS.md"
  ];
  codexText = evaluated.home.file.".codex/AGENTS.md".text;
  piText = evaluated.home.file.".pi/agent/AGENTS.md".text;
  flattenedCodexText = lib.replaceStrings [ "\n" ] [ " " ] codexText;
  count = needle: haystack: builtins.length (lib.splitString needle haystack) - 1;
in
{
  testAgentContextProjectionMatchesToolCapabilities = {
    expr = {
      sourceMappingsCorrect =
        toString evaluated.home.file.".agents/context".source == toString contextRoot
        && toString evaluated.home.file.".claude/CLAUDE.md".source == toString globalContext
        && toString evaluated.home.file.".claude/rules".source == toString rulesDirectory;
      discoveredRules = ruleNames;
      fragmentsStartAtH2 = lib.all (
        name: lib.hasPrefix "## " (builtins.readFile (rulesDirectory + "/${name}"))
      ) ruleNames;
      globalStartsAtH1 = lib.hasPrefix "# Global Configuration\n" (builtins.readFile globalContext);
      combinedOutputsEqual = codexText == piText;
      combinedStartsWithGlobal = lib.hasPrefix "# Global Configuration\n" codexText;
      combinedIncludesGlobal = count "Interact with the user in Japanese" codexText;
      combinedRuleHeadings = map (heading: count heading codexText) [
        "## AI Assistance Rules"
        "## GitHub Access Strategy"
        "## Nix Build Rules"
        "## Preferred Tools"
        "## Web Fetch Strategy"
      ];
      combinedRuleOrderCorrect =
        builtins.match ".*## AI Assistance Rules.*## GitHub Access Strategy.*## Nix Build Rules.*## Preferred Tools.*## Web Fetch Strategy.*" flattenedCodexText
        != null;
      trashPreferenceCount = count "Recoverable deletion" codexText;
      claudeGlobalExcludesRules = !lib.hasInfix "Recoverable deletion" (builtins.readFile globalContext);
      codexIsCombined = codexText != builtins.readFile globalContext;
      forces = map (path: evaluated.home.file.${path}.force) managedPaths;
    };
    expected = {
      sourceMappingsCorrect = true;
      discoveredRules = [
        "ai-assistance.md"
        "github.md"
        "nix.md"
        "tools.md"
        "web-fetch.md"
      ];
      fragmentsStartAtH2 = true;
      globalStartsAtH1 = true;
      combinedOutputsEqual = true;
      combinedStartsWithGlobal = true;
      combinedIncludesGlobal = 1;
      combinedRuleHeadings = [
        1
        1
        1
        1
        1
      ];
      combinedRuleOrderCorrect = true;
      trashPreferenceCount = 1;
      claudeGlobalExcludesRules = true;
      codexIsCombined = true;
      forces = [
        false
        false
        false
        false
        false
      ];
    };
  };
}
