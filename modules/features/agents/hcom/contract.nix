{
  flake.modules.homeManager.agent-hcom-contract = { lib, ... }: {
    key = "modules/features/agents/hcom/contract.nix#homeManager.agent-hcom-contract";

    options.dotfiles.agentIntegrations.hcom = lib.mkOption {
      internal = true;
      default = null;
      description = "hcom artifacts available when dotfiles.hcom.enable is enabled.";
      type = lib.types.nullOr (
        lib.types.submodule {
          options = {
            package = lib.mkOption { type = lib.types.package; };
            claudeHooks = lib.mkOption { type = lib.types.package; };
            codexHooks = lib.mkOption { type = lib.types.package; };
          };
        }
      );
    };
  };
}
