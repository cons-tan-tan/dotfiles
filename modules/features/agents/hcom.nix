{
  features,
  inputs,
  ...
}:
{
  features.agent-hcom = {
    name = "feature/agents/hcom";
    includes = [
      features.agents-base
      features.agent-skills-consumer
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
