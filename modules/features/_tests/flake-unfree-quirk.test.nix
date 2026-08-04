{ inputs }:
let
  mkFixture =
    producerModule:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } (
      { den, withSystem, ... }:
      {
        imports = [
          inputs.den.flakeModule
          ../../flake/den-output-routing.nix
          ../../flake/systems.nix
          ../nixpkgs.nix
        ];

        den.aspects.first-unfree-producer = producerModule.first;
        den.aspects.second-unfree-producer = producerModule.second;
        den.schema.flake-parts.includes = [
          den.aspects.first-unfree-producer
          den.aspects.second-unfree-producer
        ];

        flake.unfreeNames = withSystem "x86_64-linux" ({ config, ... }: config.dotfiles.unfreePackageNames);
      }
    );

  mergedFixture = mkFixture {
    first.flake-unfree-packages = [
      "alpha"
      "shared"
    ];
    second.flake-unfree-packages = [
      "beta"
      "shared"
    ];
  };

  invalidFixture = mkFixture {
    first.flake-unfree-packages = [ "invalid name" ];
    second.flake-unfree-packages = [ "valid" ];
  };
in
{
  testContributionsMergeAndDeduplicate = {
    expr = mergedFixture.unfreeNames;
    expected = [
      "alpha"
      "shared"
      "beta"
    ];
  };

  testInvalidContributionIsRejected = {
    expr = (builtins.tryEval (builtins.deepSeq invalidFixture.unfreeNames null)).success;
    expected = false;
  };
}
