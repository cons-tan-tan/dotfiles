{ lib }:
let
  deploy = import ../_lib/deploy.nix {
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
  succeeds =
    resources: (builtins.tryEval (builtins.deepSeq (deploy.validateResources resources) true)).success;
in
{
  testDistinctOwnerDestinationsAreAccepted = {
    expr = succeeds {
      claude = resource { trees = [ (tree ".claude/commands") ]; };
      guidance = resource { files = [ (file ".claude/CLAUDE.md") ]; };
    };
    expected = true;
  };

  testDuplicateFileDestinationIsRejected = {
    expr = succeeds {
      first = resource { files = [ (file ".config/shared") ]; };
      second = resource { files = [ (file ".config/shared") ]; };
    };
    expected = false;
  };

  testFileTreeDestinationCollisionIsRejected = {
    expr = succeeds {
      fileOwner = resource { files = [ (file ".config/shared") ]; };
      treeOwner = resource { trees = [ (tree ".config/shared") ]; };
    };
    expected = false;
  };

  testNestedDestinationsAcrossDeploymentPhasesAreRejected = {
    expr = succeeds {
      "deployments/claude" = resource { files = [ (file ".claude/settings.json") ]; };
      "static/claude" = resource { trees = [ (tree ".claude") ]; };
    };
    expected = false;
  };
}
