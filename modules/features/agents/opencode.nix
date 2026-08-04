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
      import ./_lib/home/opencode.nix {
        inherit
          config
          lib
          pkgs
          ;
      };
  };
}
