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
      }
    ];

    homeManager =
      { pkgs, ... }:
      let
        hcom = pkgs.dotfilesPackages.hcom;
      in
      {
        home.packages = [ hcom.package ];
        dotfiles.agentIntegrations.hcom = {
          inherit (hcom) package;
          inherit (hcom.integrations) claudeHooks codexHooks;
        };
      };
  };
}
