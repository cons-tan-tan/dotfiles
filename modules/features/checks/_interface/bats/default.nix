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
  featuresRoot = ../../..;
  descriptorContext = {
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
  descriptorFiles = lib.sort builtins.lessThan (
    builtins.filter (
      path:
      lib.hasInfix "/_tests/" (toString path)
      && builtins.elem (baseNameOf path) [
        "bats-fragment.nix"
        "bats-shard.nix"
      ]
    ) (lib.filesystem.listFilesRecursive featuresRoot)
  );
  callDescriptor =
    path:
    let
      declaration = import path;
      functionArgs = if builtins.isFunction declaration then builtins.functionArgs declaration else { };
      missingRequiredArgs = builtins.filter (
        name: !functionArgs.${name} && !builtins.hasAttr name descriptorContext
      ) (builtins.attrNames functionArgs);
    in
    if missingRequiredArgs != [ ] then
      throw "${toString path} requires unavailable Bats descriptor arguments: ${builtins.toJSON missingRequiredArgs}"
    else if builtins.isFunction declaration then
      declaration (builtins.intersectAttrs functionArgs descriptorContext)
    else
      declaration;
  loadDescriptor =
    path:
    if baseNameOf path == "bats-fragment.nix" then
      let
        descriptor = callDescriptor path;
      in
      if
        builtins.isAttrs descriptor
        &&
          lib.sort builtins.lessThan (builtins.attrNames descriptor) == [
            "fixture"
            "group"
            "shard"
          ]
        && builtins.isString descriptor.group
      then
        {
          inherit (descriptor) group;
          fragment = removeAttrs descriptor [ "group" ];
          standalone = false;
        }
      else
        throw "${toString path} must declare exactly group, fixture, and shard"
    else
      let
        fixturePath = dirOf path + "/bats-fixture.nix";
        shard = callDescriptor path;
        grouped = builtins.isAttrs shard && shard ? group;
      in
      if !builtins.pathExists fixturePath then
        throw "${toString path} requires a sibling bats-fixture.nix"
      else if !builtins.isAttrs shard then
        throw "${toString path} must declare a Bats shard"
      else
        {
          group = if grouped then shard.group else null;
          fragment = {
            fixture = callDescriptor fixturePath;
            shard = removeAttrs shard [ "group" ];
          };
          standalone = !grouped;
        };
  descriptors = map loadDescriptor descriptorFiles;
  groupNames = [
    "rustCli"
    "safeFetch"
    "shellWrappers"
  ];
  unknownGroups = lib.unique (
    map (descriptor: descriptor.group) (
      builtins.filter (
        descriptor: !descriptor.standalone && !(builtins.elem descriptor.group groupNames)
      ) descriptors
    )
  );
  fragments =
    builtins.listToAttrs (
      map (
        group:
        lib.nameValuePair group (
          map (descriptor: descriptor.fragment) (
            builtins.filter (descriptor: descriptor.group == group) descriptors
          )
        )
      ) groupNames
    )
    // {
      standalone = map (descriptor: descriptor.fragment) (
        builtins.filter (descriptor: descriptor.standalone) descriptors
      );
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
  declaredCatalog = import ../../_data/bats/catalog.nix {
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
    if unknownGroups != [ ] then
      throw "Unknown Bats descriptor groups: ${builtins.toJSON unknownGroups}"
    else if duplicateFixtureNames != [ ] then
      throw "Bats fixture names have multiple owners: ${builtins.toJSON duplicateFixtureNames}"
    else
      (import ../../_lib/bats/validate-catalog.nix { inherit lib; }) {
        discoveredFiles = discoveredBatsFiles;
        reservedNames = [ "bats-tests" ];
        shards = declaredCatalog;
      };
  harness = import ../../_lib/bats/harness.nix {
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
