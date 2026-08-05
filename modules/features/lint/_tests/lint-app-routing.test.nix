{ flake, pkgs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  expected = import ../_interface/app-set.nix { inherit pkgs; };
in
{
  testPublicLintAppsUseOwnerDeclaration = {
    expr = {
      markdownlint = flake.apps.${system}.markdownlint.program;
      textlint = flake.apps.${system}.textlint.program;
    };
    expected = {
      markdownlint = expected.apps.markdownlint.program;
      textlint = expected.apps.textlint.program;
    };
  };

  testPublicLintValidationsUseOwnerDeclaration = {
    expr = builtins.all (
      validation:
      builtins.elem (toString validation) (map toString flake.checks.${system}.app-scripts.paths)
    ) expected.validations;
    expected = true;
  };
}
