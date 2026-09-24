{
  flake-file.inputs = {
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
