{
  flake,
  inputs,
  pkgs,
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  fixture = inputs.flake-parts.lib.mkFlake { inherit inputs; } {
    imports = [
      inputs.den.flakeModule
      inputs.flake-file.flakeModules.dendritic
      ../../flake/den-output-routing.nix
      ../../flake/systems.nix
      ../nixpkgs.nix
      ../formatting.nix
    ];
  };
in
{
  testFormatterUsesDenTreefmtRoute = {
    expr = fixture.formatter.${system}.drvPath;
    expected = flake.formatter.${system}.drvPath;
  };

  testTreefmtCheckUsesDenTreefmtRoute = {
    expr = fixture.checks.${system}.treefmt.drvPath;
    expected = flake.checks.${system}.treefmt.drvPath;
  };

  testTreefmtCheckKeepsCiMetadata = {
    expr = fixture.checks.${system}.treefmt.meta.dotfiles.hestia.targets;
    expected = {
      aarch64-darwin = null;
      x86_64-linux = "repo-quality";
    };
  };
}
