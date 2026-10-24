{ inputs, ... }:
{
  flake-file.inputs.hunk = {
    url = "github:modem-dev/hunk";
    inputs.bun2nix.follows = "bun2nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  flake.modules.homeManager.agent-hunk = {
    key = "modules/features/agents/hunk/default.nix#homeManager.agent-hunk";
    dotfiles.agentSkillContributions = [
      {
        name = "hunk-review";
        provenance = "external";
        definition.root = inputs.hunk.outPath + "/packages/hunk/skills/hunk-review";
      }
    ];
  };
}
