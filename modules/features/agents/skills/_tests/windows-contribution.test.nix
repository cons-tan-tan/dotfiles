{
  inputs,
  lib,
  repoRoot,
}:
let
  mkHome = import ../../../checks/_lib/eval/home-fixture.nix { inherit inputs lib repoRoot; };
  evaluate =
    windows: hasSkills:
    (mkHome {
      files = [
        "platform/context.nix"
        "windows/options.nix"
        "agents/skills/options.nix"
        "agents/skills/default.nix"
      ];
      modules = hm: [
        hm.platform-context
        hm.home-base
        hm.agent-skills-consumer
        {
          dotfiles.platform = {
            environment = if windows then "wsl" else "linux";
            source = "/source/test";
            standalone = true;
            windows = lib.optionalAttrs windows {
              enable = true;
              username = "test-win";
              homedir = "/mnt/c/Users/test-win";
            };
          };
          dotfiles.agentSkillContributions = lib.optional hasSkills {
            name = "example";
            provenance = "external";
            definition.root = repoRoot + "/agents/skills/missing-tools";
          };
        }
      ];
    }).config.dotfiles.windows.staticResources;
in
{
  testConsumerWithoutProducersHasNoWindowsSourceTrees = {
    expr = evaluate true false;
    expected = { };
  };
  testConsumerWithSkillsPublishesBothWindowsDestinations = {
    expr = map (tree: tree.destination) (evaluate true true).skills.trees;
    expected = [
      ".claude/skills"
      ".agents/skills"
    ];
  };
  testLinuxSkillsDoNotCreateWindowsResources = {
    expr = evaluate false true;
    expected = { };
  };
}
