{
  den,
  inputs,
  lib,
  ...
}:
let
  ciCheck = import ../ci/_interface/check.nix { inherit lib; };
  appsFor =
    { pkgs, self', ... }:
    import ./_interface/app-set.nix {
      formatter = self'.formatter;
      inherit pkgs;
    };
in
{
  flake-file.inputs.treefmt-nix = {
    url = "github:numtide/treefmt-nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  imports = [ inputs.treefmt-nix.flakeModule ];

  den.aspects.formatting = {
    flake-parts.treefmt = {
      flakeCheck = false;
      projectRootFile = "flake.nix";
      programs = {
        nixf-diagnose = {
          enable = true;
          autoFix = true;
        };
        nixfmt.enable = true;
        rustfmt.enable = true;
        shfmt.enable = true;
      };
      settings = {
        formatter.nixf-diagnose.priority = -1;
        global.excludes = [
          ".direnv/**"
          ".git/**"
          "*.lock"
          "result"
        ];
      };
    };

    apps = args: (appsFor args).apps;
    app-validations = [
      {
        produce = args: (appsFor args).validationsByName;
      }
    ];
    checks =
      { config, ... }:
      {
        treefmt = ciCheck.annotate (ciCheck.targets.linux "repo-quality") (
          config.treefmt.build.check config.treefmt.projectRoot
        );
      };
  };

  den.schema.flake-parts.includes = [ den.aspects.formatting ];
}
