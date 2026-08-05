{
  inputs,
  lib,
}:
let
  fixtureOverlay =
    final: _prev:
    let
      mkFixture =
        pname:
        final.stdenvNoCC.mkDerivation {
          inherit pname;
          version = "1";
          dontUnpack = true;
          installPhase = ''
            mkdir -p "$out"
          '';
          meta.license = lib.licenses.unfree;
        };
    in
    {
      flake-allowed-fixture = mkFixture "flake-allowed-fixture";
      flake-denied-fixture = mkFixture "flake-denied-fixture";
    };
  pkgs = (import ../_interface).mkPkgs {
    inherit inputs;
    extraOverlays = [ fixtureOverlay ];
    unfreePackageNames = [ "flake-allowed-fixture" ];
  } "x86_64-linux";
in
{
  testNamedUnfreePackageIsAllowed = {
    expr = (builtins.tryEval pkgs.flake-allowed-fixture.drvPath).success;
    expected = true;
  };

  testUnnamedUnfreePackageIsRejected = {
    expr = (builtins.tryEval pkgs.flake-denied-fixture.drvPath).success;
    expected = false;
  };
}
