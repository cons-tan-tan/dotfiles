{ lib }:
let
  # Hestia runners cannot share uncached outputs, so groups colocate large shared
  # closures while leaving independent work parallel. Keeping each check's choice
  # beside its definition avoids a second name inventory that can survive a rename
  # while silently selecting the wrong closure layout.
  groups = [
    "configurations"
    "eval-tests"
    "package-smoke"
    "repo-quality"
    "rust-and-bats"
  ];
  systems = {
    darwin = "aarch64-darwin";
    linux = "x86_64-linux";
  };
  systemPrefixes = {
    ${systems.darwin} = "darwin";
    ${systems.linux} = "linux";
  };
  systemNames = builtins.attrNames systemPrefixes;

  targets = rec {
    bySystem =
      {
        darwin,
        linux,
      }:
      {
        ${systems.darwin} = darwin;
        ${systems.linux} = linux;
      };
    both =
      group:
      bySystem {
        darwin = group;
        linux = group;
      };
    darwin =
      group:
      bySystem {
        darwin = group;
        linux = null;
      };
    linux =
      group:
      bySystem {
        darwin = null;
        linux = group;
      };
  };

  isValidTargets =
    checkTargets:
    builtins.isAttrs checkTargets
    && builtins.attrNames checkTargets == systemNames
    && builtins.any (system: checkTargets.${system} != null) systemNames
    && builtins.all (
      system:
      let
        group = checkTargets.${system};
      in
      group == null || (builtins.isString group && builtins.elem group groups)
    ) systemNames;

  validateTargets =
    checkTargets:
    let
      targetSystems = if builtins.isAttrs checkTargets then builtins.attrNames checkTargets else [ ];
      invalidGroups = builtins.filter (
        system:
        let
          group = checkTargets.${system};
        in
        group != null && (!(builtins.isString group) || !(builtins.elem group groups))
      ) targetSystems;
    in
    if !builtins.isAttrs checkTargets then
      throw "CI check targets must be an attribute set"
    else if targetSystems != systemNames then
      throw "CI check targets must classify every build system: ${builtins.toJSON systemNames}"
    else if builtins.all (system: checkTargets.${system} == null) systemNames then
      throw "CI check targets must select at least one build system"
    else if invalidGroups != [ ] then
      throw "CI check targets contain invalid groups for systems: ${builtins.toJSON invalidGroups}"
    else
      true; # Only strictness is observed by annotate; nix-mutation-test: ignore

  evaluationComplete =
    check:
    let
      oldMeta = check.meta or { };
      oldDotfilesMeta = oldMeta.dotfiles or { };
      oldCiMeta = oldDotfilesMeta.ci or { };
    in
    if
      (oldMeta ? hestia && oldMeta.hestia ? group) || oldDotfilesMeta ? hestia || oldCiMeta ? execution
    then
      throw "CI check already has CI or canonical Hestia metadata"
    else
      check
      // {
        meta = oldMeta // {
          dotfiles = oldDotfilesMeta // {
            ci = oldCiMeta // {
              execution = "evaluation-complete";
            };
          };
        };
      };

  evaluationCompleteSet = lib.mapAttrs (_: evaluationComplete);

  composeEvaluationCompleteProducers =
    producers:
    let
      indexedProducers = lib.imap0 (index: producer: { inherit index producer; }) producers;
      invalidProducerIndexes = map (entry: entry.index) (
        builtins.filter (
          entry:
          let
            inherit (entry) producer;
          in
          !builtins.isAttrs producer
          ||
            builtins.attrNames producer != [
              "checks"
              "owner"
            ]
          || !builtins.isString producer.owner
          || producer.owner == ""
          || !builtins.isAttrs producer.checks
        ) indexedProducers
      );
      entries = lib.concatMap (
        producer:
        map (name: {
          inherit name;
          inherit (producer) owner;
        }) (builtins.attrNames producer.checks)
      ) producers;
      names = map (entry: entry.name) entries;
      duplicateNames = builtins.filter (
        name: builtins.length (builtins.filter (candidate: candidate == name) names) > 1
      ) (lib.unique names);
      collisions = map (name: {
        inherit name;
        owners = map (entry: entry.owner) (builtins.filter (entry: entry.name == name) entries);
      }) duplicateNames;
      validation =
        if invalidProducerIndexes != [ ] then
          throw "invalid evaluation-complete check producers: ${builtins.toJSON invalidProducerIndexes}"
        else if collisions != [ ] then
          throw "evaluation-complete check producer collisions: ${builtins.toJSON collisions}"
        else
          null;
      values = builtins.seq validation (
        lib.foldl' (result: producer: result // producer.checks) { } producers
      );
    in
    {
      checkNames = builtins.seq validation names;
      inherit values;
      checks = evaluationCompleteSet values;
    };

  getExecution =
    check:
    let
      oldMeta = check.meta or { };
      oldDotfilesMeta = oldMeta.dotfiles or { };
      oldCiMeta = oldDotfilesMeta.ci or { };
    in
    oldCiMeta.execution or null;

  isEvaluationComplete =
    check:
    let
      oldMeta = check.meta or { };
      oldDotfilesMeta = oldMeta.dotfiles or { };
    in
    getExecution check == "evaluation-complete"
    && !(oldDotfilesMeta ? hestia)
    && !(oldMeta ? hestia && oldMeta.hestia ? group);

  annotate =
    checkTargets: check:
    let
      oldMeta = check.meta or { };
      oldDotfilesMeta = oldMeta.dotfiles or { };
      oldCiMeta = oldDotfilesMeta.ci or { };
      validation = validateTargets checkTargets;
    in
    if
      (oldMeta ? hestia && oldMeta.hestia ? group) || oldDotfilesMeta ? hestia || oldCiMeta ? execution
    then
      throw "CI check already has CI or canonical Hestia metadata"
    else
      builtins.seq validation (
        check
        // {
          meta = oldMeta // {
            dotfiles = oldDotfilesMeta // {
              hestia.targets = checkTargets;
            };
          };
        }
      );

  annotateSet = checkTargets: lib.mapAttrs (_: annotate checkTargets);

  buildEntry = checkTargets: value: {
    targets = builtins.seq (validateTargets checkTargets) checkTargets;
    inherit value;
  };

  buildEntrySet = checkTargets: lib.mapAttrs (_: buildEntry checkTargets);

  mkBuildProducer =
    {
      entries,
      owner,
    }:
    let
      names = builtins.attrNames entries;
      invalid = builtins.filter (
        name:
        let
          entry = entries.${name};
        in
        !builtins.isAttrs entry
        ||
          builtins.attrNames entry != [
            "targets"
            "value"
          ]
        || !(isValidTargets entry.targets)
      ) names;
      validation =
        if !builtins.isString owner || owner == "" then
          throw "CI build check producer owner must be a non-empty string"
        else if invalid != [ ] then
          throw "invalid CI build check entries for ${owner}: ${builtins.toJSON invalid}"
        else
          null;
    in
    {
      inherit owner;
      checks = builtins.seq validation (
        lib.mapAttrs (_: entry: annotate entry.targets entry.value) entries
      );
      routes = builtins.seq validation (lib.mapAttrs (_: entry: entry.targets) entries);
    };

  composeBuildProducers =
    {
      producers,
      reservedCheckNames ? [ ],
    }:
    let
      indexedProducers = lib.imap0 (index: producer: { inherit index producer; }) producers;
      invalidProducerIndexes = map (entry: entry.index) (
        builtins.filter (
          entry:
          let
            inherit (entry) producer;
          in
          !builtins.isAttrs producer
          ||
            builtins.attrNames producer != [
              "checks"
              "owner"
              "routes"
            ]
          || !builtins.isString producer.owner
          || producer.owner == ""
          || !builtins.isAttrs producer.checks
          || !builtins.isAttrs producer.routes
          || builtins.attrNames producer.checks != builtins.attrNames producer.routes
        ) indexedProducers
      );
      producerEntries = lib.concatMap (
        producer:
        map (name: {
          inherit name;
          inherit (producer) owner;
        }) (builtins.attrNames producer.routes)
      ) producers;
      reservedEntries = map (name: {
        inherit name;
        owner = "reserved";
      }) reservedCheckNames;
      entries = producerEntries ++ reservedEntries;
      names = map (entry: entry.name) entries;
      duplicateNames = builtins.filter (
        name: builtins.length (builtins.filter (candidate: candidate == name) names) > 1
      ) (lib.unique names);
      collisions = map (name: {
        inherit name;
        owners = map (entry: entry.owner) (builtins.filter (entry: entry.name == name) entries);
      }) duplicateNames;
      validation =
        if invalidProducerIndexes != [ ] then
          throw "invalid CI build check producers: ${builtins.toJSON invalidProducerIndexes}"
        else if collisions != [ ] then
          throw "check owner collisions: ${builtins.toJSON collisions}"
        else
          null;
      mergeField =
        field:
        builtins.seq validation (lib.foldl' (result: producer: result // producer.${field}) { } producers);
    in
    {
      checkNames = builtins.seq validation (map (entry: entry.name) producerEntries);
      checks = mergeField "checks";
      routes = mergeField "routes";
    };

  composeRouteProducers =
    producers:
    let
      asBuildProducer = producer: {
        inherit (producer) owner routes;
        checks = lib.genAttrs (builtins.attrNames producer.routes) (_: null);
      };
    in
    (composeBuildProducers { producers = map asBuildProducer producers; }).routes;

  isClassified =
    check:
    let
      execution = getExecution check;
      checkTargets = getTargets check;
    in
    (execution == "evaluation-complete" && checkTargets == null)
    || (execution == null && checkTargets != null);

  getTargets =
    check:
    let
      oldMeta = check.meta or { };
      oldDotfilesMeta = oldMeta.dotfiles or { };
      oldCiMeta = oldDotfilesMeta.ci or { };
    in
    if oldMeta ? hestia && oldMeta.hestia ? group then
      throw "canonical checks must not define meta.hestia.group"
    else if oldDotfilesMeta ? hestia && oldCiMeta ? execution then
      throw "CI check has conflicting execution metadata"
    else if !(oldDotfilesMeta ? hestia && oldDotfilesMeta.hestia ? targets) then
      null
    else
      oldDotfilesMeta.hestia.targets;

  mkHestiaChecks =
    {
      checks,
      routes ? lib.mapAttrs (_: getTargets) checks,
      system,
    }:
    let
      prefix = systemPrefixes.${system} or (throw "unsupported Hestia build system: ${system}");
      checkNames = builtins.attrNames checks;
      routeNames = builtins.attrNames routes;
      missingRoutes = lib.subtractLists routeNames checkNames;
      unexpectedRoutes = lib.subtractLists checkNames routeNames;
      invalidRoutes = builtins.filter (name: !(isValidTargets routes.${name})) routeNames;
      selectedNames = builtins.filter (
        name: isValidTargets routes.${name} && routes.${name}.${system} != null
      ) routeNames;
      assignments = lib.imap0 (index: name: {
        inherit name;
        jobName =
          let
            jobCount = builtins.length selectedNames;
          in
          builtins.elemAt selectedNames (index - (builtins.div index jobCount) * jobCount);
      }) routeNames;
    in
    if missingRoutes != [ ] || unexpectedRoutes != [ ] || invalidRoutes != [ ] then
      throw "invalid Hestia CI checks for ${system}: ${
        builtins.toJSON {
          inherit
            invalidRoutes
            missingRoutes
            unexpectedRoutes
            ;
        }
      }"
    else if routeNames != [ ] && selectedNames == [ ] then
      throw "Hestia routes for ${system} require at least one selected build job"
    else
      lib.genAttrs selectedNames (
        name:
        let
          check = checks.${name};
          assignedNames = map (assignment: assignment.name) (
            builtins.filter (assignment: assignment.jobName == name) assignments
          );
          missing = builtins.filter (assignedName: getTargets checks.${assignedName} == null) assignedNames;
          invalid = builtins.filter (
            assignedName:
            let
              checkTargets = getTargets checks.${assignedName};
            in
            checkTargets != null && !(isValidTargets checkTargets)
          ) assignedNames;
          metadataMismatch = builtins.filter (
            assignedName: getTargets checks.${assignedName} != routes.${assignedName}
          ) assignedNames;
          wrongSystem = builtins.filter (
            assignedName:
            routes.${assignedName}.${system} != null && (checks.${assignedName}.system or null) != system
          ) assignedNames;
          oldMeta = check.meta or { };
          group = routes.${name}.${system};
        in
        if missing != [ ] || invalid != [ ] || metadataMismatch != [ ] || wrongSystem != [ ] then
          throw "invalid Hestia CI checks for ${system}: ${
            builtins.toJSON {
              inherit
                invalid
                metadataMismatch
                missing
                wrongSystem
                ;
            }
          }"
        else
          check
          // {
            meta = oldMeta // {
              hestia = (oldMeta.hestia or { }) // {
                group = "${prefix}-${group}";
              };
            };
          }
      );

  mkHestiaJobs =
    {
      checksBySystem,
      evaluationCompleteCheckNamesBySystem,
      routesBySystem,
    }:
    let
      checkSystems = builtins.attrNames checksBySystem;
      evaluationCompleteSystems = builtins.attrNames evaluationCompleteCheckNamesBySystem;
      routeSystems = builtins.attrNames routesBySystem;
    in
    if
      checkSystems != systemNames
      || evaluationCompleteSystems != systemNames
      || routeSystems != systemNames
    then
      throw "Hestia jobs must provide every build system: ${builtins.toJSON systemNames}"
    else
      lib.genAttrs systemNames (
        system:
        let
          checks = checksBySystem.${system};
          evaluationCompleteCheckNames = evaluationCompleteCheckNamesBySystem.${system};
          unknown = builtins.filter (name: !(builtins.hasAttr name checks)) evaluationCompleteCheckNames;
          jobs = mkHestiaChecks {
            checks = removeAttrs checks evaluationCompleteCheckNames;
            routes = routesBySystem.${system};
            inherit system;
          };
          jobNames = builtins.attrNames jobs;
          assignments = lib.imap0 (index: name: {
            inherit name;
            jobName =
              let
                jobCount = builtins.length jobNames;
              in
              builtins.elemAt jobNames (index - (builtins.div index jobCount) * jobCount);
          }) evaluationCompleteCheckNames;
        in
        if unknown != [ ] then
          throw "invalid evaluation-complete CI checks for ${system}: ${builtins.toJSON { inherit unknown; }}"
        else if evaluationCompleteCheckNames != [ ] && jobNames == [ ] then
          throw "evaluation-complete CI checks for ${system} require at least one Hestia build job"
        else
          lib.mapAttrs (
            jobName: job:
            let
              assignedNames = map (assignment: assignment.name) (
                builtins.filter (assignment: assignment.jobName == jobName) assignments
              );
              invalidEvaluationComplete = builtins.filter (
                name: !(isEvaluationComplete checks.${name})
              ) assignedNames;
            in
            if invalidEvaluationComplete != [ ] then
              throw "invalid evaluation-complete CI checks for ${system}: ${
                builtins.toJSON { inherit invalidEvaluationComplete; }
              }"
            else
              job
          ) jobs
      );

  selectBuildChecks =
    {
      checks,
      evaluationCompleteCheckNames,
      system,
    }:
    let
      unknown = builtins.filter (name: !(builtins.hasAttr name checks)) evaluationCompleteCheckNames;
    in
    if unknown != [ ] then
      throw "evaluation-complete CI checks are missing for ${system}: ${builtins.toJSON unknown}"
    else
      removeAttrs checks evaluationCompleteCheckNames;

  validateCheckManifest =
    {
      buildRoutesBySystem,
      checkNamesBySystem,
      evaluationCompleteCheckNamesBySystem,
    }:
    let
      configuredSystems = builtins.attrNames checkNamesBySystem;
      declaredSystems = builtins.attrNames evaluationCompleteCheckNamesBySystem;
      routeSystems = builtins.attrNames buildRoutesBySystem;
      validateEvaluationCompleteSystem =
        system:
        let
          checkNames = checkNamesBySystem.${system};
          declaredNames = evaluationCompleteCheckNamesBySystem.${system};
          duplicateNames = builtins.filter (
            name: builtins.length (builtins.filter (candidate: candidate == name) declaredNames) > 1
          ) (lib.unique declaredNames);
          unknown = builtins.filter (name: !(builtins.elem name checkNames)) declaredNames;
        in
        if duplicateNames != [ ] || unknown != [ ] then
          throw "invalid evaluation-complete CI check manifest for ${system}: ${
            builtins.toJSON { inherit duplicateNames unknown; }
          }"
        else
          true;
      validateBuildSystem =
        system:
        let
          checkNames = checkNamesBySystem.${system};
          evaluationCompleteNames = evaluationCompleteCheckNamesBySystem.${system};
          expectedBuildNames = lib.subtractLists evaluationCompleteNames checkNames;
          routes = buildRoutesBySystem.${system};
          routeNames = builtins.attrNames routes;
          missing = lib.subtractLists routeNames expectedBuildNames;
          unexpected = lib.subtractLists expectedBuildNames routeNames;
          invalid = builtins.filter (name: !(isValidTargets routes.${name})) routeNames;
        in
        if missing != [ ] || unexpected != [ ] || invalid != [ ] then
          throw "invalid Hestia build check manifest for ${system}: ${
            builtins.toJSON { inherit invalid missing unexpected; }
          }"
        else
          true;
      routeRefs = lib.concatMap (
        system:
        map (name: {
          inherit name system;
          targets = buildRoutesBySystem.${system}.${name};
        }) (builtins.attrNames buildRoutesBySystem.${system})
      ) routeSystems;
      routeNames = lib.unique (map (ref: ref.name) routeRefs);
      refsFor = name: builtins.filter (ref: ref.name == name) routeRefs;
      inconsistent = builtins.filter (
        name:
        let
          targetSets = map (ref: ref.targets) (refsFor name);
        in
        !(builtins.all (targets: targets == builtins.head targetSets) targetSets)
      ) routeNames;
      targetsByName = lib.genAttrs routeNames (name: (builtins.head (refsFor name)).targets);
      declaredButMissing = lib.concatMap (
        name:
        map (system: "${system}.${name}") (
          builtins.filter (
            system:
            targetsByName.${name}.${system} != null && !(builtins.hasAttr name buildRoutesBySystem.${system})
          ) systemNames
        )
      ) routeNames;
    in
    if configuredSystems != declaredSystems then
      throw "evaluation-complete checks must use matching systems: ${
        builtins.toJSON { inherit configuredSystems declaredSystems; }
      }"
    else if routeSystems != configuredSystems then
      throw "build check manifests must use matching systems: ${
        builtins.toJSON { inherit configuredSystems routeSystems; }
      }"
    else if !(builtins.all validateEvaluationCompleteSystem configuredSystems) then
      throw "evaluation-complete manifest validation returned false"
    else if !(builtins.all validateBuildSystem routeSystems) then
      throw "Hestia build manifest validation returned false"
    else if inconsistent != [ ] || declaredButMissing != [ ] then
      throw "inconsistent cross-system Hestia manifest: ${
        builtins.toJSON { inherit declaredButMissing inconsistent; }
      }"
    else
      true;

in
{
  inherit
    annotate
    annotateSet
    buildEntry
    buildEntrySet
    composeBuildProducers
    composeEvaluationCompleteProducers
    composeRouteProducers
    evaluationComplete
    evaluationCompleteSet
    isClassified
    isEvaluationComplete
    mkHestiaChecks
    mkHestiaJobs
    mkBuildProducer
    selectBuildChecks
    targets
    validateCheckManifest
    ;
}
