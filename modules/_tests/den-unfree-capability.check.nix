{
  inputs,
  lib,
  pkgs,
}:
let
  tests = import ./den-unfree-capability.suite.nix {
    inherit inputs lib;
  };
  result = lib.debug.throwTestFailures {
    failures = lib.debug.runTests tests;
  };
in
builtins.seq result (pkgs.runCommand "den-unfree-capability-tests" { } ''touch "$out"'')
