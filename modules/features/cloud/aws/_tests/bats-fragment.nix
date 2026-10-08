{ pkgs, subjects }:
let
  awsConfigReconcileTestBaseline = pkgs.writeText "aws-config-reconcile-test-baseline" ''
    [profile test]
    region = baseline
    output = json
  '';
  awsConfigReconcileTestPackage = pkgs.callPackage ../_packages/reconcile-package.nix {
    baselineFile = awsConfigReconcileTestBaseline;
    configHelper = subjects.awsConfigHelper;
    managedSections = [ "profile test" ];
  };
in
{
  group = "shellWrappers";
  fixture = {
    nativeBuildInputs = [
      awsConfigReconcileTestPackage
    ];
    environment = {
      AWS_CONFIG_RECONCILE_TEST_PACKAGE = awsConfigReconcileTestPackage;
    };
    requiredEnvironment = [
      "AWS_CONFIG_RECONCILE_TEST_PACKAGE"
    ];
  };
  shard = {
    testFiles = [
      "modules/features/cloud/aws/_tests/aws-config-activation.bats"
    ];
    sourceFiles = [
      "modules/features/cloud/aws/_packages/reconcile-package.nix"
    ];
  };
}
