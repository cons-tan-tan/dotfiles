{
  configurationTargets,
  flake,
  pkgs,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  targets = configurationTargets.${system};
  expected = import ../_interface/app-set.nix {
    inherit pkgs;
    username = targets.username;
  };
in
{
  testPublicApplyNixSettingsAppUsesOwnerDeclaration = {
    expr = flake.apps.${system}.apply-nix-settings.program;
    expected = expected.apps.apply-nix-settings.program;
  };

  testPublicApplyNixSettingsValidationUsesOwnerDeclaration = {
    expr = builtins.elem (toString expected.validationsByName.apply-nix-settings) (
      map toString flake.checks.${system}.app-scripts.paths
    );
    expected = true;
  };
}
