{
  caseName,
  nixpkgsPath,
  repoRoot,
}:
let
  lib = import (nixpkgsPath + "/lib");
  protocol = import (repoRoot + "/modules/features/checks/_lib/home-contract-protocol.nix") {
    inherit lib;
  };
  force = value: builtins.deepSeq value true;
  mkContract = descriptor: {
    type = "derivation";
    name = descriptor.name;
  };
  load =
    declaration:
    force (
      protocol.loadContract {
        context = { };
        contractName = "demo";
        inherit declaration mkContract;
        source = "fixture";
      }
    );
  cases = {
    emptyDiscovery = {
      expression = force (
        protocol.validateDiscovery {
          contractNames = [ ];
        }
      );
      expectedFragment = "No Feature-owned Home contracts were discovered";
    };
    duplicateName = {
      expression = force (
        protocol.validateDiscovery {
          contractNames = [
            "demo"
            "demo"
          ];
        }
      );
      expectedFragment = ''Duplicate Feature-owned Home contract names: ["demo"]'';
    };
    missingRequiredArgument = {
      expression = load ({ unavailable }: unavailable);
      expectedFragment = ''requires unavailable Home contract arguments: ["unavailable"]'';
    };
    nonDescriptor = {
      expression = load true;
      expectedFragment = "must return a Home contract descriptor";
    };
    unknownDescriptorField = {
      expression = load {
        describe = _: true;
        expected = _: true;
        extra = true;
      };
      expectedFragment = "must contain exactly describe and expected";
    };
    invalidDescriptorField = {
      expression = load {
        describe = true;
        expected = _: true;
      };
      expectedFragment = "descriptor fields must be functions";
    };
  };
in
if caseName == null then cases else cases.${caseName}.expression
