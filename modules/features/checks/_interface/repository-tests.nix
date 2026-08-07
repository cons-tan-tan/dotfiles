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
  testDiscovery = import ../_lib/test-discovery.nix { inherit lib; };
  composeUniqueChecks = import ../_lib/compose.nix { inherit ciCheck lib; };
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
let
  evaluationCompleteComposition = ciCheck.composeEvaluationCompleteProducers eval.evaluationCompleteProducers;
  buildComposition = composeUniqueChecks {
    producers =
      eval.buildProducers
      ++ [
        rust.producer
        bats.producer
      ]
      ++ manual.producers;
    reservedCheckNames = reservedCheckNames ++ evaluationCompleteComposition.checkNames;
  };
in
{
  buildChecks = buildComposition.checks;
  buildRoutes = buildComposition.routes;
  evaluationCompleteChecks = evaluationCompleteComposition.values;
}
