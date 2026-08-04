{
  inputs,
  lib,
  pkgs,
}:
let
  tests = import ../../modules/_tests/den-unfree-capability.nix {
    inherit inputs lib;
  };
  result = lib.debug.throwTestFailures {
    failures = lib.debug.runTests tests;
  };
in
builtins.seq result (pkgs.runCommand "den-unfree-capability-tests" { } ''touch "$out"'')
