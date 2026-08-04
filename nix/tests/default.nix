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
  username,
  reservedCheckNames ? [ ],
}:
let
  nixRoot = ../.;
  repoRoot = ../..;
  modulesRoot = repoRoot + "/modules";
  testDiscovery = import ./test-discovery.nix { inherit lib; };
  composeUniqueChecks = import ./compose.nix { inherit lib; };
  cacheSettings = import ../lib/cache-settings.nix;
  configurationTargets = import ../../modules/entities/_lib/configuration-targets.nix {
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
      username
      ;
  };
  eval = import ./eval {
    inherit
      ciCheck
      lib
      modulesRoot
      nixRoot
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
      nixRoot
      pkgs
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
  manual = import ./checks {
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
