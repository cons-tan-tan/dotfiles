{
  getEnv,
  getFlake,
  repoRoot,
  system,
}:
let
  flake = getFlake (toString repoRoot);
  pkgs = (import (repoRoot + "/modules/features/nixpkgs/_interface")).mkPkgs {
    inputs = flake.inputs;
    unfreePackageNames = [ "codex-app" ];
  } system;
in
pkgs.dotfilesPackages.${getEnv "UPDATE_PINS_PACKAGE"}
