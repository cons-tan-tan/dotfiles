{
  caseName,
  nixpkgsPath,
  repoRoot,
}:
let
  fixturePin.assets.x86_64-linux = {
    name = "fixture-x86_64";
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };
  cases.unsupportedSystem = {
    expression = builtins.seq nixpkgsPath (
      (import (repoRoot + "/modules/features/nixpkgs/_lib/mk-pinned-asset.nix") {
        pin = fixturePin;
        system = "aarch64-darwin";
        label = "fixture";
      }).asset
    );
    expectedFragment = "fixture: unsupported system 'aarch64-darwin'";
  };
in
if caseName == null then cases else cases.${caseName}.expression
