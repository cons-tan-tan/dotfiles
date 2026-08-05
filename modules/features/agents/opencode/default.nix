{ features, ... }:
{
  features.agent-opencode = {
    name = "feature/agents/opencode";
    includes = [
      features.agent-guidance
      features.agent-herdr
    ];
    homeManager =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      import ./_lib/home.nix {
        inherit
          config
          lib
          pkgs
          ;
      };
  };
}
