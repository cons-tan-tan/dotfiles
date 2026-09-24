{
  config,
  inputs,
  ...
}:
{
  # CLI pin と agent skill source は package-owned updateScript が揃える。
  flake-file.inputs.hcom-src = {
    url = "github:aannoo/hcom/v0.7.21";
    flake = false;
  };

  flake.modules.homeManager.agent-hcom = {
    key = "modules/features/agents/hcom/default.nix#homeManager.agent-hcom";
    imports = [
      config.flake.modules.homeManager.agents-base
      config.flake.modules.homeManager.agent-hcom-contract
      (
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          hcom = pkgs.dotfilesPackages.hcom;
        in
        {
          options.dotfiles.hcom.enable = lib.mkEnableOption "hcom CLI, hooks, and agent skill";

          config = lib.mkIf config.dotfiles.hcom.enable {
            home.packages = [ hcom.package ];
            dotfiles.agentIntegrations.hcom = {
              inherit (hcom) package;
              inherit (hcom.integrations) claudeHooks codexHooks;
            };
          };
        }
      )
    ];
    dotfiles.agentSkillContributions = [
      {
        name = "hcom-agent-messaging";
        provenance = "hcom";
        definition.root = inputs.hcom-src.outPath + "/skills/hcom-agent-messaging";
        enable = config: config.dotfiles.hcom.enable;
      }
    ];
  };
}
