{
  inputs,
  pkgs,
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  fixture = inputs.flake-parts.lib.mkFlake { inherit inputs; } (
    { den, ... }:
    {
      imports = [
        inputs.den.flakeModule
        ../../nixpkgs.nix
        ../../../flake/den-output-routing.nix
        ../../../flake/systems.nix
      ];

      den.aspects.check-routing-probe.checks =
        { pkgs, ... }:
        {
          probe = pkgs.dotfilesPackages.difit;
        };

      den.schema.flake-parts.includes = [ den.aspects.check-routing-probe ];
    }
  );
in
{
  testChecksUseFlakePartsPkgs = {
    expr = fixture.checks.${system}.probe.drvPath;
    expected = pkgs.dotfilesPackages.difit.drvPath;
  };

  testChecksHaveSingleRootRoute = {
    expr = builtins.attrNames fixture.checks.${system};
    expected = [ "probe" ];
  };
}
