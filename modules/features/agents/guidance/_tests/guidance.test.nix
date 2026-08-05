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
        ../_lib/home.nix
        {
          home = {
            username = "test";
            homeDirectory = "/home/test";
            stateVersion = "24.11";
          };
        }
      ];
    }).config;
  contextRoot = ../_data/context;
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
  stripTrailingNewlines =
    text: if lib.hasSuffix "\n" text then stripTrailingNewlines (lib.removeSuffix "\n" text) else text;
  readFragment = path: stripTrailingNewlines (builtins.readFile path);
  globalFragment = readFragment globalContext;
  ruleFragments = map (name: readFragment (rulesDirectory + "/${name}")) ruleNames;
  expectedCombinedContext = lib.concatStringsSep "\n\n" ([ globalFragment ] ++ ruleFragments) + "\n";
  codexText = evaluated.home.file.".codex/AGENTS.md".text;
  piText = evaluated.home.file.".pi/agent/AGENTS.md".text;
  count = needle: haystack: builtins.length (lib.splitString needle haystack) - 1;
in
{
  testAgentContextProjectionMatchesDiscoveredFragments = {
    expr = {
      sourceMappings = {
        agents = toString evaluated.home.file.".agents/context".source;
        claudeGlobal = toString evaluated.home.file.".claude/CLAUDE.md".source;
        claudeRules = toString evaluated.home.file.".claude/rules".source;
      };
      globalStartsAtH1 = lib.hasPrefix "# " globalFragment;
      rulesStartAtH2 = map (fragment: lib.hasPrefix "## " fragment) ruleFragments;
      codexText = codexText;
      piMatchesCodex = piText == codexText;
      ruleOccurrences = map (fragment: count fragment codexText) ruleFragments;
      forces = map (path: evaluated.home.file.${path}.force) managedPaths;
    };
    expected = {
      sourceMappings = {
        agents = toString contextRoot;
        claudeGlobal = toString globalContext;
        claudeRules = toString rulesDirectory;
      };
      globalStartsAtH1 = true;
      rulesStartAtH2 = map (_: true) ruleFragments;
      codexText = expectedCombinedContext;
      piMatchesCodex = true;
      ruleOccurrences = map (_: 1) ruleFragments;
      forces = map (_: false) managedPaths;
    };
  };
}
