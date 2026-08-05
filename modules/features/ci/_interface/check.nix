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
      true;

  annotate =
    checkTargets: check:
    let
      oldMeta = check.meta or { };
      oldDotfilesMeta = oldMeta.dotfiles or { };
      validation = validateTargets checkTargets;
    in
    if oldDotfilesMeta ? hestia then
      throw "CI check already has dotfiles Hestia metadata"
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

  getTargets =
    check:
    let
      oldMeta = check.meta or { };
    in
    if oldMeta ? hestia && oldMeta.hestia ? group then
      throw "canonical checks must not define meta.hestia.group"
    else if !(oldMeta ? dotfiles && oldMeta.dotfiles ? hestia && oldMeta.dotfiles.hestia ? targets) then
      null
    else
      oldMeta.dotfiles.hestia.targets;

  mkHestiaChecks =
    {
      checks,
      system,
    }:
    let
      prefix = systemPrefixes.${system} or (throw "unsupported Hestia build system: ${system}");
      checkNames = builtins.attrNames checks;
      missing = builtins.filter (name: getTargets checks.${name} == null) checkNames;
      invalid = builtins.filter (
        name:
        let
          checkTargets = getTargets checks.${name};
        in
        checkTargets != null && !(isValidTargets checkTargets)
      ) checkNames;
      selectedNames = builtins.filter (
        name:
        let
          checkTargets = getTargets checks.${name};
        in
        checkTargets != null && checkTargets.${system} != null
      ) checkNames;
      wrongSystem = builtins.filter (name: (checks.${name}.system or null) != system) selectedNames;
      entries = map (
        name:
        let
          check = checks.${name};
          group = (getTargets check).${system};
        in
        {
          inherit group name;
          drvPath = check.drvPath;
        }
      ) selectedNames;
      entriesByDrv = builtins.groupBy (entry: builtins.unsafeDiscardStringContext entry.drvPath) entries;
      conflictingDrvs = lib.filterAttrs (
        _: drvEntries: builtins.length (lib.unique (map (entry: entry.group) drvEntries)) > 1
      ) entriesByDrv;
    in
    if missing != [ ] || invalid != [ ] || wrongSystem != [ ] || conflictingDrvs != { } then
      throw "invalid Hestia CI checks for ${system}: ${
        builtins.toJSON {
          conflictingDrvPaths = builtins.attrNames conflictingDrvs;
          inherit invalid missing wrongSystem;
        }
      }"
    else
      lib.genAttrs selectedNames (
        name:
        let
          check = checks.${name};
          oldMeta = check.meta or { };
          group = (getTargets check).${system};
        in
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
    checksBySystem:
    let
      configuredSystems = builtins.attrNames checksBySystem;
      checkRefs = lib.concatMap (
        system:
        map (name: {
          check = checksBySystem.${system}.${name};
          inherit name system;
        }) (builtins.attrNames checksBySystem.${system})
      ) configuredSystems;
      missing = map (ref: "${ref.system}.${ref.name}") (
        builtins.filter (ref: getTargets ref.check == null) checkRefs
      );
      invalid = map (ref: "${ref.system}.${ref.name}") (
        builtins.filter (
          ref:
          let
            checkTargets = getTargets ref.check;
          in
          checkTargets != null && !(isValidTargets checkTargets)
        ) checkRefs
      );
      checkNames = lib.unique (map (ref: ref.name) checkRefs);
      refsFor = name: builtins.filter (ref: ref.name == name) checkRefs;
      inconsistent = builtins.filter (
        name:
        let
          targetSets = map (ref: getTargets ref.check) (refsFor name);
          first = builtins.head targetSets;
        in
        !(builtins.all (checkTargets: checkTargets == first) targetSets)
      ) checkNames;
      targetsByName = lib.genAttrs checkNames (name: getTargets (builtins.head (refsFor name)).check);
      declaredButMissing = lib.concatMap (
        name:
        map (system: "${system}.${name}") (
          builtins.filter (
            system: targetsByName.${name}.${system} != null && !(builtins.hasAttr name checksBySystem.${system})
          ) systemNames
        )
      ) checkNames;
    in
    if configuredSystems != systemNames then
      throw "Hestia jobs must provide every build system: ${builtins.toJSON systemNames}"
    else if missing != [ ] || invalid != [ ] then
      throw "invalid canonical Hestia metadata: ${builtins.toJSON { inherit invalid missing; }}"
    else if inconsistent != [ ] || declaredButMissing != [ ] then
      throw "inconsistent cross-system Hestia metadata: ${
        builtins.toJSON {
          inherit declaredButMissing inconsistent;
        }
      }"
    else
      lib.mapAttrs (system: checks: mkHestiaChecks { inherit checks system; }) checksBySystem;
in
{
  inherit
    annotate
    annotateSet
    mkHestiaChecks
    mkHestiaJobs
    targets
    ;
}
