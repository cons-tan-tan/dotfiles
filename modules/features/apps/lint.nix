{
  den,
  inputs,
  lib,
  ...
}:
let
  mkAspect = import ./_lib/mk-common-den-aspect.nix {
    inherit den inputs lib;
  };
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

  den.aspects.lint-apps = mkAspect { group = "lint"; };

  den.schema.flake-parts.includes = [ den.aspects.lint-apps ];
}
