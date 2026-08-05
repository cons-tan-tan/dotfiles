{ flake, pkgs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  updatePins = import ../_interface;
  expected = updatePins.mkAppSet { inherit pkgs; };
in
{
  testPublicUpdatePinsAppUsesOwnerDeclaration = {
    expr = flake.apps.${system}.update-pins.program;
    expected = expected.apps.update-pins.program;
  };

  testPublicUpdatePinsValidationUsesOwnerDeclaration = {
    expr = builtins.elem (toString expected.validationsByName.update-pins) (
      map toString flake.checks.${system}.app-scripts.paths
    );
    expected = true;
  };
}
