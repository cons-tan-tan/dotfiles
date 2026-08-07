{
  ciCheck,
  currentTargets,
  flake,
  lib,
  pkgs,
  repoRoot,
  subjects,
  username,
}:
let
  featuresRoot = ../../..;
  descriptorContext = {
    inherit
      ciCheck
      currentTargets
      flake
      lib
      pkgs
      repoRoot
      subjects
      username
      ;
  };
  descriptorFiles = lib.sort builtins.lessThan (
    builtins.filter (
      path: baseNameOf path == "manual-check.nix" && lib.hasInfix "/_tests/" (toString path)
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
      throw "${toString path} requires unavailable manual check arguments: ${builtins.toJSON missingRequiredArgs}"
    else if builtins.isFunction declaration then
      declaration (builtins.intersectAttrs functionArgs descriptorContext)
    else
      declaration;
  descriptors = map (
    path:
    let
      descriptor = callDescriptor path;
    in
    if
      builtins.isAttrs descriptor
      &&
        lib.sort builtins.lessThan (builtins.attrNames descriptor) == [
          "artifacts"
          "buildEntries"
          "owner"
        ]
      && builtins.isString descriptor.owner
      && builtins.isList descriptor.artifacts
      && builtins.isAttrs descriptor.buildEntries
    then
      descriptor
    else
      throw "${toString path} must declare exactly owner, artifacts, and buildEntries"
  ) descriptorFiles;
  artifacts = lib.concatMap (descriptor: descriptor.artifacts) descriptors;
  invalidArtifacts = builtins.filter (
    artifact:
    !builtins.isAttrs artifact
    ||
      builtins.attrNames artifact != [
        "name"
        "path"
      ]
    || !builtins.isString artifact.name
    || artifact.name == ""
    || !lib.isDerivation artifact.path
  ) artifacts;
  artifactNames = map (artifact: artifact.name) artifacts;
  duplicateArtifactNames = builtins.filter (
    name: builtins.length (builtins.filter (candidate: candidate == name) artifactNames) > 1
  ) (lib.unique artifactNames);
  descriptorValidation =
    if descriptorFiles == [ ] then
      throw "No Feature-owned manual checks were discovered"
    else if invalidArtifacts != [ ] then
      throw "Manual check descriptors contain invalid artifacts"
    else if duplicateArtifactNames != [ ] then
      throw "Manual check artifact names have multiple owners: ${builtins.toJSON duplicateArtifactNames}"
    else
      null;
  descriptorProducers = map (
    descriptor:
    ciCheck.mkBuildProducer {
      inherit (descriptor) owner;
      entries = descriptor.buildEntries;
    }
  ) descriptors;
  packageSmokeProducer = ciCheck.mkBuildProducer {
    owner = "Feature-owned package smoke checks";
    entries.package-smoke-tests = ciCheck.buildEntry (ciCheck.targets.both "package-smoke") (
      pkgs.linkFarm "package-smoke-tests" artifacts
    );
  };
in
{
  producers = builtins.seq descriptorValidation (
    [
      (import ../../_tests/repository-quality.nix {
        inherit
          ciCheck
          lib
          pkgs
          repoRoot
          ;
      })
    ]
    ++ descriptorProducers
    ++ [ packageSmokeProducer ]
  );
}
