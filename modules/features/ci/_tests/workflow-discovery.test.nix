{ lib }:
let
  workflowDiscovery = import ./workflows.nix { inherit lib; };
in
{
  testWorkflowDiscoverySelectsSortedYamlFiles = {
    expr = workflowDiscovery.fromEntries {
      "z.yaml" = "regular";
      "a.yml" = "regular";
      "ignored.txt" = "regular";
      "nested.yaml" = "directory";
    };
    expected = [
      ".github/workflows/a.yml"
      ".github/workflows/z.yaml"
    ];
  };

  testWorkflowDiscoveryRejectsEmptyDirectory = {
    expr = (builtins.tryEval (workflowDiscovery.fromEntries { })).success;
    expected = false;
  };
}
