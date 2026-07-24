{ pkgs, lib, ... }:
let
  profiles = {
    "profile nagase" = {
      region = "ap-northeast-1";
      output = "json";
      # login_session を認識しないツール (Terraform S3 backend, Starship等) 向けのワークアラウンド
      credential_process = "aws configure export-credentials --profile nagase --format process";
    };
  };

  # aws login は credential_process があるプロファイルへの実行を拒否するため除外
  loginProfiles = lib.mapAttrs (_: v: removeAttrs v [ "credential_process" ]) profiles;

  baselineFile = pkgs.writeText "aws-config-baseline" (lib.generators.toINI { } profiles);
  loginConfigFile = pkgs.writeText "aws-config-login" (lib.generators.toINI { } loginProfiles);
  configHelper = pkgs.callPackage ../../../packages/aws/config-helper { };

  awsLoginWrapper = pkgs.dotfilesPackages.aws.mkLoginPackage {
    inherit loginConfigFile;
  };
  awsConfigReconcile = pkgs.callPackage ../../../packages/aws/reconcile-package.nix {
    inherit baselineFile configHelper;
    managedSections = lib.attrNames profiles;
  };
in
{
  home.packages = with pkgs; [
    awscli2
    awsLoginWrapper
  ];

  # AWS config はmutableなため、宣言baselineへmanaged login_sessionだけを復元する。
  # loginと同じlock/atomic publishを使い、run経由でactivationのdry-runを維持する。
  home.activation.awsConfigMerge = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${lib.getExe awsConfigReconcile}
  '';
}
