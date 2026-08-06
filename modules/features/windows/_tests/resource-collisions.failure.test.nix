{
  caseName,
  nixpkgsPath,
  repoRoot,
}:
let
  lib = import (nixpkgsPath + "/lib");
  deploy = import (repoRoot + "/modules/features/windows/_interface/deploy.nix") {
    inherit lib;
    pkgs = { };
  };
  resource =
    {
      files ? [ ],
      trees ? [ ],
    }:
    {
      directories = [ ];
      inherit files trees;
    };
  file = destination: { inherit destination; };
  tree = destination: { inherit destination; };
  force = resources: builtins.deepSeq (deploy.validateResources resources) true;
  claim = owner: kind: destination: {
    inherit destination kind owner;
  };
  expectedCollision =
    left: right:
    "Windows companion resource destinations have multiple owners: ${
      builtins.toJSON [ { inherit left right; } ]
    }";
  cases = {
    duplicateFileDestination = {
      expression = force {
        first = resource { files = [ (file ".config/shared") ]; };
        second = resource { files = [ (file ".config/shared") ]; };
      };
      expectedFragment = expectedCollision (claim "first" "file" ".config/shared") (
        claim "second" "file" ".config/shared"
      );
    };
    fileTreeDestinationCollision = {
      expression = force {
        fileOwner = resource { files = [ (file ".config/shared") ]; };
        treeOwner = resource { trees = [ (tree ".config/shared") ]; };
      };
      expectedFragment = expectedCollision (claim "fileOwner" "file" ".config/shared") (
        claim "treeOwner" "tree" ".config/shared"
      );
    };
    nestedDeploymentDestinations = {
      expression = force {
        "deployments/claude" = resource { files = [ (file ".claude/settings.json") ]; };
        "static/claude" = resource { trees = [ (tree ".claude") ]; };
      };
      expectedFragment = expectedCollision (claim "deployments/claude" "file" ".claude/settings.json") (
        claim "static/claude" "tree" ".claude"
      );
    };
  };
in
if caseName == null then cases else cases.${caseName}.expression
