{
  flake-file.inputs = {
    den.url = "github:denful/den/2040b61346a7215fd7b7f51d4a457544b6e597d0";
    flake-file.url = "github:denful/flake-file/v0.6.0";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs-lib";
    };
    import-tree.url = "github:vic/import-tree/v0.2.0";
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    nixpkgs-lib.follows = "nixpkgs";
    rustsec-advisory-db = {
      url = "github:RustSec/advisory-db";
      flake = false;
    };
    supported-systems = {
      url = "path:./nix/systems";
      flake = false;
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}
