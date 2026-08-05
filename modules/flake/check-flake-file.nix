{
  config,
  lib,
  ...
}:
let
  ciCheck = import ../features/ci/_interface/check.nix { inherit lib; };
in
{
  perSystem =
    { pkgs, ... }:
    {
      checks.check-flake-file = lib.mkForce (
        ciCheck.annotate (ciCheck.targets.both "repo-quality") (config.flake-file.check-flake-file pkgs)
      );
    };
}
