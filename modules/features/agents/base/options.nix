{ lib, ... }:
{
  flake.modules.homeManager.agents-base = {
    key = "modules/features/agents/base/options.nix#homeManager.agents-base";
    options.dotfiles.agentCommandPolicyContributions = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            owner = lib.mkOption { type = lib.types.str; };
            policy = lib.mkOption { type = lib.types.attrs; };
          };
        }
      );
      default = [ ];
      description = "Command policy fragments, with ownership checked before compilation.";
    };
  };
}
