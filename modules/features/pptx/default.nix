{
  den,
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

  den.aspects.pptx-toolchain = {
    apps = args: (appsFor args).apps;
    app-validations = [
      {
        produce = args: (appsFor args).validationsByName;
      }
    ];
  };

  features.pptx-agent-skill = {
    name = "feature/pptx/agent-skill";
    agent-skills = [
      {
        name = "pptx";
        provenance = "external";
        definition = {
          root = inputs.anthropic-skills.outPath + "/skills/pptx";
          customization.body =
            { original, ... }:
            ''

              > **Local override**: run shell commands in this skill through the
              > declarative PPTX tool environment:
              >
              > `nix run dotfiles#pptx -- <command>`
              >
              > Examples:
              >
              > `nix run dotfiles#pptx -- python -m markitdown input.pptx`
              > `nix run dotfiles#pptx -- pdftoppm -jpeg -r 150 output.pdf slide`
              >
              > Helper scripts such as `python scripts/thumbnail.py ...` are also
              > resolved from the installed `/pptx` skill when the current project
              > does not have its own `scripts/` directory.
            ''
            + original;
        };
      }
    ];
  };

  den.schema.flake-parts.includes = [ den.aspects.pptx-toolchain ];
}
