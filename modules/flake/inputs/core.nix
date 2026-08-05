{
  flake-file.inputs = {
    den.url = "github:denful/den/2040b61346a7215fd7b7f51d4a457544b6e597d0";
    den-gen-algebra = {
      url = "github:sini/gen-algebra/dd682674edad388c439c6f2b08f84c31feec1b68";
      flake = false;
    };
    den-gen-schema = {
      url = "github:sini/gen-schema/4bd0f6eb1799bf3c38eb3707419157b1f70eb1f5";
      flake = false;
    };
    den-nix-effects = {
      url = "github:denful/nix-effects/c3c68a45deb892d028711eeff8b80937e30a90dd";
      flake = false;
    };
    flake-file.url = "github:denful/flake-file/v0.6.0";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs-lib";
    };
    import-tree.url = "github:vic/import-tree/v0.2.0";
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    nixpkgs-lib.follows = "nixpkgs";
    supported-systems = {
      url = "path:./modules/flake/_data/systems";
      flake = false;
    };
  };
}
