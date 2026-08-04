{
  cacheSettings,
  ciCheck,
  lib,
  pkgs,
  publicApps,
  repoRoot,
  subjects,
  username,
}:
let
  workflowDiscovery = import ./workflows.nix { inherit lib; };
  workflowFiles = workflowDiscovery.discover (repoRoot + "/.github/workflows");
  fixtures = {
    updatePins = import ./fixtures/update-pins.nix {
      inherit lib pkgs subjects;
    };
    safeFetch = import ./fixtures/safe-fetch.nix {
      inherit lib pkgs subjects;
    };
    rustCli = import ./fixtures/rust-cli.nix {
      inherit lib publicApps subjects;
    };
    shellWrappers = import ./fixtures/shell-wrappers.nix {
      inherit
        lib
        pkgs
        publicApps
        subjects
        username
        ;
    };
    workflowPolicy = import ./fixtures/workflow-policy.nix {
      inherit cacheSettings pkgs;
    };
  };
  declaredCatalog = import ./catalog.nix {
    inherit ciCheck workflowFiles;
  };
  catalog = map (shard: removeAttrs shard [ "fixture" ] // fixtures.${shard.fixture}) declaredCatalog;
  discoveredBatsFiles = lib.sort builtins.lessThan (
    map (path: lib.removePrefix "${toString repoRoot}/" (toString path)) (
      builtins.filter (path: lib.hasSuffix ".bats" (toString path)) (
        lib.filesystem.listFilesRecursive (repoRoot + "/bats")
      )
    )
  );
  catalogValidation = (import ./validate-catalog.nix { inherit lib; }) {
    discoveredFiles = discoveredBatsFiles;
    reservedNames = [ "bats-tests" ];
    shards = declaredCatalog;
  };
  harness = import ./harness.nix {
    inherit lib pkgs repoRoot;
  };
  applicableShards = builtins.filter (
    shard: shard.platformPredicate pkgs.stdenv.hostPlatform
  ) catalog;
  shardEntries = map (
    shard:
    lib.nameValuePair shard.name (
      ciCheck.annotate (shard.ciTargets or (ciCheck.targets.both "rust-and-bats")) (
        harness (
          removeAttrs shard [
            "ciTargets"
            "platformPredicate"
          ]
        )
      )
    )
  ) applicableShards;
  shardChecks = lib.listToAttrs shardEntries;
  # The aggregate contains a Linux-only policy shard; portable shards are
  # already built individually on Darwin, so a fake Darwin aggregate adds no signal.
  aggregate = ciCheck.annotate (ciCheck.targets.linux "rust-and-bats") (
    pkgs.linkFarm "bats-tests" (
      map (shard: {
        inherit (shard) name;
        path = shardChecks.${shard.name};
      }) applicableShards
    )
  );
in
{
  producer = {
    owner = "Bats checks";
    checks = builtins.seq catalogValidation (
      lib.listToAttrs (shardEntries ++ [ (lib.nameValuePair "bats-tests" aggregate) ])
    );
  };
}
