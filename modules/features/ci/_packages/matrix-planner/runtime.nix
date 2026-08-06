let
  repoRoot = ../../../../..;
  flake = builtins.getAttr "getFlake" builtins (toString repoRoot);
  nixpkgsInterface = import ../../../nixpkgs/_interface;
  pkgs =
    (nixpkgsInterface.mkPkgs {
      inherit (flake) inputs;
    })
      builtins.currentSystem;
in
pkgs.dotfilesPackages.ci-matrix-planner
