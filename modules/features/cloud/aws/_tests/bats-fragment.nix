{ pkgs, subjects }:
let
  awsLoginFixture = pkgs.writeShellApplication {
    name = "aws";
    text = ''
      : "''${TEST_TMPDIR:?}"
      printf '%s\n' "$@" >"$TEST_TMPDIR/aws-args"
      if [[ "''${AWS_LOGIN_TEST_MODE:-success}" == fail ]]; then
        exit 7
      fi
      : "''${AWS_CONFIG_FILE:?}"
      printf '%s\n' 'login_session = fixture-session' >>"$AWS_CONFIG_FILE"
    '';
  };
  awsLoginTestBaseline = pkgs.writeText "aws-login-test-baseline" ''
    [profile test]
    output = json
  '';
  awsLoginTestPackage = pkgs.callPackage ../_packages/login-package.nix {
    awscli2 = awsLoginFixture;
    configHelper = subjects.awsConfigHelper;
    loginConfigFile = awsLoginTestBaseline;
  };
  awsConfigReconcileTestBaseline = pkgs.writeText "aws-config-reconcile-test-baseline" ''
    [profile test]
    region = baseline
    credential_process = command
  '';
  awsConfigReconcileTestPackage = pkgs.callPackage ../_packages/reconcile-package.nix {
    baselineFile = awsConfigReconcileTestBaseline;
    configHelper = subjects.awsConfigHelper;
    managedSections = [ "profile test" ];
  };
in
{
  fixture = {
    nativeBuildInputs = [
      awsConfigReconcileTestPackage
      awsLoginTestPackage
    ];
    environment = {
      AWS_CONFIG_RECONCILE_TEST_PACKAGE = awsConfigReconcileTestPackage;
      AWS_LOGIN_TEST_PACKAGE = awsLoginTestPackage;
    };
    requiredEnvironment = [
      "AWS_CONFIG_RECONCILE_TEST_PACKAGE"
      "AWS_LOGIN_TEST_PACKAGE"
    ];
  };
  shard = {
    testFiles = [
      "modules/features/cloud/aws/_tests/aws-config-activation.bats"
      "modules/features/cloud/aws/_tests/aws-login.bats"
    ];
    sourceFiles = [
      "modules/features/cloud/aws/_packages/aws-login.sh"
      "modules/features/cloud/aws/_packages/reconcile-package.nix"
    ];
  };
}
