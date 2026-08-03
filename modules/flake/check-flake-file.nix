{
  config,
  lib,
  ...
}:
let
  ciCheck = import ../../nix/lib/ci-check.nix { inherit lib; };
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
