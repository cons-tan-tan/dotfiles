{
  flake,
  pkgs,
  repoRoot,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  expected = import ../_lib/mk-app-set.nix { inherit pkgs repoRoot; };
in
{
  testPublicApplySecretsAppUsesOwnerDeclaration = {
    expr = flake.apps.${system}.apply-secrets.program;
    expected = expected.apps.apply-secrets.program;
  };

  testPublicApplySecretsValidationUsesOwnerDeclaration = {
    expr = builtins.elem (toString expected.validationsByName.apply-secrets) (
      map toString flake.checks.${system}.app-scripts.paths
    );
    expected = true;
  };
}
