{
  config,
  lib,
  ...
}:
let
  ciCheck = import ../features/ci/_interface/check.nix { inherit lib; };
in
{
  imports = [ ../features/ci/_interface/options.nix ];

  perSystem =
    { pkgs, ... }:
    let
      producer = ciCheck.mkBuildProducer {
        owner = "flake-file checks";
        entries.check-flake-file = ciCheck.buildEntry (ciCheck.targets.both "repo-quality") (
          config.flake-file.check-flake-file pkgs
        );
      };
    in
    {
      checks.check-flake-file = lib.mkForce producer.checks.check-flake-file;
      dotfiles.ci.buildRouteProducers = [
        {
          inherit (producer) owner routes;
        }
      ];
    };
}
