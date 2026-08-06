{ lib }:
let
  protocol = import ../_lib/home-contract-protocol.nix { inherit lib; };
  fakeDerivation = name: {
    type = "derivation";
    inherit name;
  };
  mkContract = descriptor: fakeDerivation descriptor.name;
in
{
  testAcceptsDiscoveredContracts = {
    expr = builtins.seq (protocol.validateDiscovery {
      contractNames = [
        "alpha"
        "beta"
      ];
    }) true;
    expected = true;
  };

  testInjectsOnlyDeclaredArguments = {
    expr =
      protocol.loadContract {
        context = {
          available = true;
          ignored = true;
        };
        contractName = "demo";
        declaration = { available }: {
          describe = _: available;
          expected = _: true;
        };
        inherit mkContract;
        source = "fixture";
      } == fakeDerivation "demo-home-contract";
    expected = true;
  };

  testAllowsOptionalUnavailableArgument = {
    expr =
      protocol.loadContract {
        context = { };
        contractName = "demo";
        declaration =
          {
            optional ? true,
          }:
          {
            describe = _: optional;
            expected = _: true;
          };
        inherit mkContract;
        source = "fixture";
      } == fakeDerivation "demo-home-contract";
    expected = true;
  };
}
