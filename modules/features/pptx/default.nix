{
  inputs,
  ...
}:
let
  appsFor = { pkgs, ... }: import ./_interface/app-set.nix { inherit inputs pkgs; };
in
{
  flake-file.inputs = {
    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
    };
    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
    };
  };

  flake.modules.homeManager.pptx-agent-skill = {
    key = "modules/features/pptx/default.nix#homeManager.pptx-agent-skill";
    dotfiles.agentSkillContributions = [
      {
        name = "pptx";
        provenance = "external";
        definition = {
          root = inputs.anthropic-skills.outPath + "/skills/pptx";
          customization.body.program = ./_data/agent-skills/pptx;
        };
      }
    ];
  };

  perSystem =
    { pkgs, ... }:
    let
      appSet = appsFor { inherit pkgs; };
    in
    {
      inherit (appSet) apps;
      dotfiles.appValidationSets = [ appSet.validationsByName ];
    };
}
