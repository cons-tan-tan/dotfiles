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
  paths = [
    ".claude/CLAUDE.md"
    ".codex/AGENTS.md"
    ".pi/agent/AGENTS.md"
  ];
  texts = map (path: evaluated.home.file.${path}.text) paths;
  count = needle: haystack: builtins.length (lib.splitString needle haystack) - 1;
in
{
  testAgentsShareOneGeneratedGuidance = {
    expr = {
      allEqual = lib.all (text: text == builtins.head texts) texts;
      baseDirectiveCount = count "Interact with the user in Japanese" (builtins.head texts);
      trashGuidanceCount = count "Use `trash` instead of `rm`." (builtins.head texts);
      forces = map (path: evaluated.home.file.${path}.force) paths;
    };
    expected = {
      allEqual = true;
      baseDirectiveCount = 1;
      trashGuidanceCount = 1;
      forces = [
        false
        false
        false
      ];
    };
  };
}
