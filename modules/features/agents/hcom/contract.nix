{
  features.agent-hcom-contract = {
    name = "feature/agents/hcom/contract";
    homeManager = { lib, ... }: {
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
  };
}
