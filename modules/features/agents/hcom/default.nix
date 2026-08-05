{
  features,
  inputs,
  ...
}:
{
  # CLI pin と agent skill source は update-pins が同じ release へ揃える。
  flake-file.inputs.hcom-src = {
    url = "github:aannoo/hcom/v0.7.21";
    flake = false;
  };

  features.agent-hcom = {
    name = "feature/agents/hcom";
    includes = [
      features.agents-base
      features.agent-hcom-contract
    ];

    agent-skills = [
      {
        name = "hcom-agent-messaging";
        provenance = "hcom";
        definition.root = inputs.hcom-src.outPath + "/skills/hcom-agent-messaging";
        enable = config: config.dotfiles.hcom.enable;
      }
    ];

    homeManager =
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
      };
  };
}
