{ inputs, ... }:
{
  flake-file.inputs.ax = {
    url = "github:yusukebe/ax/v0.1.23";
    inputs.bun2nix.follows = "bun2nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  flake.modules.homeManager.agent-ax = {
    key = "modules/features/agents/ax.nix#homeManager.agent-ax";
    imports = [
      (
        { pkgs, ... }:
        {
          home.packages = [ inputs.ax.packages.${pkgs.stdenv.hostPlatform.system}.ax ];
        }
      )
    ];
    dotfiles.agentSkillContributions = [
      {
        name = "ax";
        provenance = "external";
        definition.root = inputs.ax.outPath + "/skills/ax";
      }
    ];
    # ax can send mutating HTTP methods. The agent policy intentionally allows
    # the managed CLI as a whole; task-level authorization remains separate.
    dotfiles.agentCommandPolicyContributions = [
      {
        owner = "feature/agents/ax";
        policy.commands.ax = true;
      }
    ];
  };
}
