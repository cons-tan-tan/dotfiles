{ lib, pkgs }:
let
  cliTools = import ./cli-tools.nix;
  allowedLinuxRoutes = [
    "dotfiles-package"
    "home-packages"
    "none"
    "programs"
  ];
  isNonEmptyString = value: builtins.isString value && value != "";
  entryLabel =
    index: tool:
    if tool ? winget && tool.winget ? id then tool.winget.id else "entry-${toString index}";
  coreValid =
    tool:
    tool ? winget
    && builtins.isAttrs tool.winget
    && tool.winget ? id
    && isNonEmptyString tool.winget.id
    && tool.winget ? packageId
    && isNonEmptyString tool.winget.packageId
    && tool ? linux
    && builtins.isString tool.linux;
  validTools = builtins.filter coreValid cliTools;

  invalidCoreEntries = builtins.filter (label: label != null) (
    lib.imap0 (index: tool: if coreValid tool then null else entryLabel index tool) cliTools
  );
  invalidLinuxRoutes = map (tool: {
    inherit (tool.winget) id;
    inherit (tool) linux;
  }) (builtins.filter (tool: !(builtins.elem tool.linux allowedLinuxRoutes)) validTools);
  invalidNixpkgsAttrOwnership = map (tool: tool.winget.id) (
    builtins.filter (tool: (tool.linux == "home-packages") != (tool ? nixpkgsAttr)) validTools
  );
  invalidNixpkgsAttrs =
    map
      (tool: {
        inherit (tool.winget) id;
        attr = tool.nixpkgsAttr;
      })
      (
        builtins.filter (
          tool:
          tool ? nixpkgsAttr
          && (
            !(isNonEmptyString tool.nixpkgsAttr)
            || !(builtins.hasAttr tool.nixpkgsAttr pkgs)
            || !(lib.isDerivation pkgs.${tool.nixpkgsAttr})
          )
        ) validTools
      );

  invalidWingetMetadata = map (tool: tool.winget.id) (
    builtins.filter (
      tool:
      (tool.winget ? elevated && !(builtins.isBool tool.winget.elevated))
      || (tool.winget ? description && !(isNonEmptyString tool.winget.description))
      || (
        tool.winget ? dependsOn
        && (
          !(builtins.isList tool.winget.dependsOn) || !(builtins.all isNonEmptyString tool.winget.dependsOn)
        )
      )
    ) validTools
  );
  duplicates =
    values:
    builtins.filter (
      value: builtins.length (builtins.filter (candidate: candidate == value) values) > 1
    ) (lib.unique values);
  wingetIds = map (tool: tool.winget.id) validTools;
  packageIds = map (tool: tool.winget.packageId) validTools;

  dependenciesFor = tool: tool.winget.dependsOn or [ ];
  unresolvedDependencies = lib.concatMap (
    tool:
    map (dependency: {
      owner = tool.winget.id;
      inherit dependency;
    }) (builtins.filter (dependency: !(builtins.elem dependency wingetIds)) (dependenciesFor tool))
  ) validTools;
  selfDependencies = map (tool: tool.winget.id) (
    builtins.filter (tool: builtins.elem tool.winget.id (dependenciesFor tool)) validTools
  );
  dependencyGraph = lib.listToAttrs (
    map (tool: lib.nameValuePair tool.winget.id (dependenciesFor tool)) validTools
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
  cyclicIds = builtins.filter hasCycleFrom wingetIds;
in
{
  testCoreSchema = {
    expr = invalidCoreEntries;
    expected = [ ];
  };

  testLinuxRoutes = {
    expr = invalidLinuxRoutes;
    expected = [ ];
  };

  testNixpkgsAttrOwnership = {
    expr = invalidNixpkgsAttrOwnership;
    expected = [ ];
  };

  testNixpkgsAttrsResolveToPackages = {
    expr = invalidNixpkgsAttrs;
    expected = [ ];
  };

  testWingetMetadata = {
    expr = invalidWingetMetadata;
    expected = [ ];
  };

  testWingetIdsAreUnique = {
    expr = duplicates wingetIds;
    expected = [ ];
  };

  testPackageIdsAreUnique = {
    expr = duplicates packageIds;
    expected = [ ];
  };

  testDependenciesResolve = {
    expr = unresolvedDependencies;
    expected = [ ];
  };

  testDependenciesDoNotReferenceSelf = {
    expr = selfDependencies;
    expected = [ ];
  };

  testDependencyGraphIsAcyclic = {
    expr = cyclicIds;
    expected = [ ];
  };
}
