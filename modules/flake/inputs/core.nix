{
  flake-file.inputs = {
    flake-file.url = "github:denful/flake-file/v0.7.0";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs-lib";
    };
    import-tree.url = "github:denful/import-tree/v0.3.0";
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    nixpkgs-lib.follows = "nixpkgs";
    supported-systems = {
      url = "path:./modules/flake/_data/systems";
      flake = false;
    };
  };
}
