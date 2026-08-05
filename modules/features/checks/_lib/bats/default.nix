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
  fragments = import ./fragments.nix {
    inherit
      cacheSettings
      ciCheck
      lib
      pkgs
      publicApps
      repoRoot
      subjects
      username
      ;
  };
  duplicates =
    values:
    builtins.filter (
      value: builtins.length (builtins.filter (candidate: candidate == value) values) > 1
    ) (lib.unique values);
  mergeFragments = ownerFragments: {
    fixture =
      let
        environmentNames = lib.concatMap (
          fragment: builtins.attrNames fragment.fixture.environment
        ) ownerFragments;
        duplicateEnvironmentNames = duplicates environmentNames;
      in
      if duplicateEnvironmentNames != [ ] then
        throw "Bats fixture environment names have multiple owners: ${builtins.toJSON duplicateEnvironmentNames}"
      else
        {
          nativeBuildInputs = lib.concatMap (fragment: fragment.fixture.nativeBuildInputs) ownerFragments;
          environment = lib.foldl' (
            environment: fragment: environment // fragment.fixture.environment
          ) { } ownerFragments;
          requiredEnvironment = lib.unique (
            lib.concatMap (fragment: fragment.fixture.requiredEnvironment) ownerFragments
          );
        };
    shard = {
      testFiles = lib.concatMap (fragment: fragment.shard.testFiles) ownerFragments;
      sourceFiles = lib.concatMap (fragment: fragment.shard.sourceFiles) ownerFragments;
    };
  };
  safeFetch = mergeFragments fragments.safeFetch;
  rustCli = mergeFragments fragments.rustCli;
  shellWrappers = mergeFragments fragments.shellWrappers;
  standaloneFixtureNames = map (fragment: fragment.shard.fixture) fragments.standalone;
  fixedFixtureNames = [
    "safeFetch"
    "rustCli"
    "shellWrappers"
  ];
  duplicateFixtureNames = duplicates (standaloneFixtureNames ++ fixedFixtureNames);
  standaloneFixtures = lib.listToAttrs (
    map (fragment: lib.nameValuePair fragment.shard.fixture fragment.fixture) fragments.standalone
  );
  fixtures = standaloneFixtures // {
    safeFetch = safeFetch.fixture;
    rustCli = rustCli.fixture;
    shellWrappers = shellWrappers.fixture;
  };
  declaredCatalog = import ./catalog.nix {
    safeFetch = safeFetch.shard;
    rustCli = rustCli.shard;
    shellWrappers = shellWrappers.shard;
    standaloneShards = map (fragment: fragment.shard) fragments.standalone;
  };
  catalog = map (shard: removeAttrs shard [ "fixture" ] // fixtures.${shard.fixture}) declaredCatalog;
  discoveredBatsFiles = lib.sort builtins.lessThan (
    map (path: lib.removePrefix "${toString repoRoot}/" (toString path)) (
      builtins.filter (path: lib.hasSuffix ".bats" (toString path)) (
        lib.filesystem.listFilesRecursive repoRoot
      )
    )
  );
  catalogValidation =
    if duplicateFixtureNames != [ ] then
      throw "Bats fixture names have multiple owners: ${builtins.toJSON duplicateFixtureNames}"
    else
      (import ./validate-catalog.nix { inherit lib; }) {
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
