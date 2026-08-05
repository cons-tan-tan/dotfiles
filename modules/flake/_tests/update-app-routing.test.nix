{ flake, pkgs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  expected = import ../_lib/mk-update-app-set.nix { inherit pkgs; };
in
{
  testPublicFlakeUpdateAppUsesOwnerDeclaration = {
    expr = flake.apps.${system}.update.program;
    expected = expected.apps.update.program;
  };

  testPublicFlakeUpdateValidationUsesOwnerDeclaration = {
    expr = builtins.elem (toString expected.validationsByName.update) (
      map toString flake.checks.${system}.app-scripts.paths
    );
    expected = true;
  };
}
