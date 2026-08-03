{ lib }:
let
  discovery = import ./test-discovery.nix { inherit lib; };
  classified = discovery.classify [
    "/repo/nix/alpha.test.nix"
    "/repo/modules/feature/_tests/beta.test.nix"
    "/repo/modules/feature/_tests/gamma.failure.test.nix"
    "/repo/modules/feature/module.nix"
  ];
in
{
  testClassifiesTestsAcrossSourceRoots = {
    expr = {
      tests = map discovery.checkName classified.testFiles;
      failures = map discovery.failureCheckName classified.failureTestFiles;
    };
    expected = {
      tests = [
        "alpha-tests"
        "beta-tests"
      ];
      failures = [ "gamma-failure-tests" ];
    };
  };

  testRejectsDuplicateBasenamesAcrossSourceRoots = {
    expr = discovery.duplicateNames [
      (discovery.checkName "/repo/nix/shared.test.nix")
      (discovery.checkName "/repo/modules/feature/_tests/shared.test.nix")
    ];
    expected = [ "shared-tests" ];
  };
}
