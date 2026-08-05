{
  flake,
  inputs,
  pkgs,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  expected = import ../_lib/mk-app-set.nix { inherit inputs pkgs; };
in
{
  testPublicPptxAppUsesOwnerDeclaration = {
    expr = flake.apps.${system}.pptx.program;
    expected = expected.apps.pptx.program;
  };

  testPublicPptxValidationUsesOwnerDeclaration = {
    expr = builtins.elem (toString expected.validationsByName.pptx) (
      map toString flake.checks.${system}.app-scripts.paths
    );
    expected = true;
  };
}
