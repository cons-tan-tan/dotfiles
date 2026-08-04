{
  features,
  inputs,
  ...
}:
{
  flake-file.inputs.codex-plugin-cc = {
    url = "github:openai/codex-plugin-cc";
    flake = false;
  };

  features.agent-claude = {
    name = "feature/agents/claude";
    includes = [
      features.agents-base
      features.agent-herdr
    ];
    homeManager =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      import ./_lib/home/claude.nix {
        inherit
          config
          inputs
          lib
          pkgs
          ;
      };
  };
}
