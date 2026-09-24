{ lib, ... }:
{
  flake.modules.homeManager.agent-skills-consumer = {
    key = "modules/features/agents/skills/options.nix#homeManager.agent-skills-consumer";
    options.dotfiles.agentSkillContributions = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption { type = lib.types.str; };
            provenance = lib.mkOption {
              type = lib.types.enum [
                "external"
                "local"
                "hcom"
              ];
            };
            definition = lib.mkOption { type = lib.types.attrs; };
            enable = lib.mkOption {
              type = lib.types.functionTo lib.types.bool;
              default = _: true;
            };
          };
        }
      );
      default = [ ];
      description = "Agent skills contributed by the selected home features.";
    };
  };
}
