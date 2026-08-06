{
  caseName,
  nixpkgsPath,
  repoRoot,
}:
let
  lib = import (nixpkgsPath + "/lib");
  workflowDiscovery = import (repoRoot + "/modules/features/ci/_tests/workflows.nix") {
    inherit lib;
  };
  cases.emptyDirectory = {
    expression = workflowDiscovery.fromEntries { };
    expectedFragment = "workflow discovery found no .yml or .yaml files";
  };
in
if caseName == null then cases else cases.${caseName}.expression
