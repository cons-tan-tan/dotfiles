{
  den,
  inputs,
  lib,
  ...
}:
let
  ciCheck = import ../../nix/lib/ci-check.nix { inherit lib; };
in
{
  flake-file.inputs.treefmt-nix = {
    url = "github:numtide/treefmt-nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  imports = [ inputs.treefmt-nix.flakeModule ];

  den.classes.treefmt = { };
  den.policies.treefmt-to-flake-parts = _: [
    (den.lib.policy.route {
      fromClass = "treefmt";
      intoClass = "flake-parts";
      path = [ "treefmt" ];
      adaptArgs = { config, ... }: config.allModuleArgs;
    })
  ];

  den.aspects.formatting.treefmt = {
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
      formatter.nixf-diagnose.excludes = [ "nix/packages/**/bun.nix" ];
      global.excludes = [
        ".direnv/**"
        ".git/**"
        "*.lock"
        "result"
      ];
    };
  };

  den.aspects.formatting-check.checks =
    { config, ... }:
    {
      treefmt = ciCheck.annotate (ciCheck.targets.linux "repo-quality") (
        config.treefmt.build.check config.treefmt.projectRoot
      );
    };

  den.schema.flake-parts.includes = [
    den.policies.treefmt-to-flake-parts
    den.aspects.formatting
    den.aspects.formatting-check
  ];
}
