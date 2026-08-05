{
  advisoryDb,
  advisoryDbLastModified,
  ciCheck,
  den,
  flake,
  homeManager,
  inputs,
  lib,
  llmAgents,
  pkgs,
  publicApps,
  repoRoot,
  username,
  reservedCheckNames ? [ ],
}:
let
  modulesRoot = repoRoot + "/modules";
  testDiscovery = import ./test-discovery.nix { inherit lib; };
  composeUniqueChecks = import ./compose.nix { inherit lib; };
  cacheSettings = (import ../../platform/nix-settings/_interface).cache;
  configurationTargets = import ../../../flake/_interface/configuration-targets.nix {
    inherit lib;
  };
  currentTargets = configurationTargets {
    inherit den;
    system = pkgs.stdenv.hostPlatform.system;
  };
  testContext = {
    inherit
      ciCheck
      den
      flake
      homeManager
      inputs
      lib
      llmAgents
      pkgs
      repoRoot
      username
      ;
  };
  eval = import ./eval {
    inherit
      ciCheck
      lib
      modulesRoot
      pkgs
      repoRoot
      testContext
      testDiscovery
      ;
  };
  rust = import ./rust {
    inherit
      advisoryDb
      advisoryDbLastModified
      ciCheck
      lib
      modulesRoot
      pkgs
      repoRoot
      ;
  };
  bats = import ./bats {
    inherit
      cacheSettings
      ciCheck
      lib
      pkgs
      publicApps
      repoRoot
      username
      ;
    subjects = rust.subjects;
  };
  manual = import ./manual {
    inherit
      ciCheck
      currentTargets
      flake
      lib
      pkgs
      repoRoot
      username
      ;
    subjects = rust.subjects;
  };
in
composeUniqueChecks {
  producers =
    eval.producers
    ++ [
      rust.producer
      bats.producer
    ]
    ++ manual.producers;
  inherit reservedCheckNames;
}
