{
  inputs,
  lib,
}:
let
  feature =
    (import ../default.nix {
      features = { };
      inherit inputs lib;
    }).features.agent-skills-consumer;
  evaluate =
    skills:
    (lib.evalModules {
      modules = [
        {
          options = {
            home.homeDirectory = lib.mkOption { type = lib.types.str; };
            dotfiles.agentSkills.externalSkills = lib.mkOption {
              type = lib.types.attrs;
              default = { };
            };
            dotfiles.windows.staticResources = lib.mkOption {
              type = lib.types.attrs;
              default = { };
            };
          };
          config = {
            home.homeDirectory = "/home/test";
            dotfiles.agentSkills.externalSkills = skills;
          };
        }
        feature.windows
      ];
    }).config.dotfiles.windows.staticResources;
in
{
  testConsumerWithoutProducersHasNoWindowsSourceTrees = {
    expr = evaluate { };
    expected = { };
  };

  testConsumerWithSkillsPublishesBothWindowsDestinations = {
    expr = map (tree: tree.destination) (evaluate { example = { }; }).skills.trees;
    expected = [
      ".claude/skills"
      ".agents/skills"
    ];
  };
}
