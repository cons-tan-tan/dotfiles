{ lib, pkgs }:
entries:
let
  isNonEmptyString = value: builtins.isString value && value != "";
  allowedEntryAttrs = [
    "id"
    "nix"
    "winget"
  ];
  allowedNixAttrs = [
    "nixpkgsAttr"
    "route"
  ];
  allowedWingetAttrs = [
    "dependsOn"
    "description"
    "elevated"
    "packageId"
    "source"
  ];
  validNixRoutes = [
    "dotfiles-package"
    "home-packages"
    "programs"
  ];
  duplicates =
    values:
    builtins.filter (
      value: builtins.length (builtins.filter (candidate: candidate == value) values) > 1
    ) (lib.unique values);
  validateNix =
    id: projection:
    if projection == null then
      null
    else
      assert lib.assertMsg (builtins.isAttrs projection)
        "cli-tools.${id}.nix must be an attribute set or null";
      assert lib.assertMsg (lib.all (name: lib.elem name allowedNixAttrs) (
        builtins.attrNames projection
      )) "cli-tools.${id}.nix contains unknown fields";
      assert lib.assertMsg (
        projection ? route && lib.elem projection.route validNixRoutes
      ) "cli-tools.${id}.nix.route is invalid";
      assert lib.assertMsg (
        (projection.route == "home-packages") == (projection ? nixpkgsAttr)
      ) "cli-tools.${id}.nix.nixpkgsAttr must be present exactly for home-packages";
      assert lib.assertMsg (
        !(projection ? nixpkgsAttr)
        || (
          isNonEmptyString projection.nixpkgsAttr
          && builtins.hasAttr projection.nixpkgsAttr pkgs
          && lib.isDerivation pkgs.${projection.nixpkgsAttr}
        )
      ) "cli-tools.${id}.nix.nixpkgsAttr must resolve to a package";
      projection;
  validateWinget =
    id: projection:
    if projection == null then
      null
    else
      assert lib.assertMsg (builtins.isAttrs projection)
        "cli-tools.${id}.winget must be an attribute set or null";
      assert lib.assertMsg (lib.all (name: lib.elem name allowedWingetAttrs) (
        builtins.attrNames projection
      )) "cli-tools.${id}.winget contains unknown fields";
      assert lib.assertMsg (
        projection ? packageId && isNonEmptyString projection.packageId
      ) "cli-tools.${id}.winget.packageId is required";
      assert lib.assertMsg (
        !(projection ? source) || isNonEmptyString projection.source
      ) "cli-tools.${id}.winget.source must be a non-empty string";
      assert lib.assertMsg (
        !(projection ? elevated) || builtins.isBool projection.elevated
      ) "cli-tools.${id}.winget.elevated must be boolean";
      assert lib.assertMsg (
        !(projection ? description) || isNonEmptyString projection.description
      ) "cli-tools.${id}.winget.description must be a non-empty string";
      assert lib.assertMsg (
        !(projection ? dependsOn)
        || (builtins.isList projection.dependsOn && builtins.all isNonEmptyString projection.dependsOn)
      ) "cli-tools.${id}.winget.dependsOn must contain non-empty IDs";
      projection;
  validateEntry =
    entry:
    assert lib.assertMsg (builtins.isAttrs entry) "cli-tools entries must be attribute sets";
    assert lib.assertMsg (lib.all (name: lib.elem name allowedEntryAttrs) (
      builtins.attrNames entry
    )) "cli-tools entry contains unknown fields";
    assert lib.assertMsg (
      entry ? id && isNonEmptyString entry.id
    ) "cli-tools entry requires a non-empty id";
    let
      checked = {
        inherit (entry) id;
        nix = validateNix entry.id (entry.nix or null);
        winget = validateWinget entry.id (entry.winget or null);
      };
    in
    assert lib.assertMsg (
      checked.nix != null || checked.winget != null
    ) "cli-tools.${entry.id} must target Nix, WinGet, or both";
    checked;
  # An aspect can be reached through more than one named variant. Identical
  # emissions are idempotent; distinct declarations for the same ID remain an
  # error below.
  checked = lib.unique (map validateEntry entries);
  ids = map (entry: entry.id) checked;
  wingetEntries = builtins.filter (entry: entry.winget != null) checked;
  wingetIds = map (entry: entry.id) wingetEntries;
  packageIds = map (entry: entry.winget.packageId) wingetEntries;
  dependenciesFor = entry: entry.winget.dependsOn or [ ];
  unresolvedDependencies = lib.concatMap (
    entry: builtins.filter (dependency: !(builtins.elem dependency wingetIds)) (dependenciesFor entry)
  ) wingetEntries;
  selfDependencies = builtins.filter (
    entry: builtins.elem entry.id (dependenciesFor entry)
  ) wingetEntries;
  dependencyGraph = lib.listToAttrs (
    map (entry: lib.nameValuePair entry.id (dependenciesFor entry)) wingetEntries
  );
  hasCycleFrom =
    start:
    let
      visit =
        path: node:
        if builtins.elem node path then
          true
        else
          builtins.any (visit (path ++ [ node ])) (dependencyGraph.${node} or [ ]);
    in
    visit [ ] start;
  cyclicIds = builtins.filter hasCycleFrom (builtins.attrNames dependencyGraph);
in
assert lib.assertMsg (
  duplicates ids == [ ]
) "cli-tools contains duplicate IDs: ${lib.concatStringsSep ", " (duplicates ids)}";
assert lib.assertMsg (duplicates packageIds == [ ])
  "cli-tools contains duplicate WinGet package IDs: ${lib.concatStringsSep ", " (duplicates packageIds)}";
assert lib.assertMsg (unresolvedDependencies == [ ])
  "cli-tools contains unresolved WinGet dependencies: ${lib.concatStringsSep ", " unresolvedDependencies}";
assert lib.assertMsg (
  selfDependencies == [ ]
) "cli-tools contains self-referencing WinGet dependencies";
assert lib.assertMsg (
  cyclicIds == [ ]
) "cli-tools contains a WinGet dependency cycle: ${lib.concatStringsSep ", " cyclicIds}";
{
  inherit checked;
  nixHomePackages = map (entry: pkgs.${entry.nix.nixpkgsAttr}) (
    builtins.filter (entry: entry.nix != null && entry.nix.route == "home-packages") checked
  );
  winget = map (entry: { inherit (entry) id winget; }) wingetEntries;
}
