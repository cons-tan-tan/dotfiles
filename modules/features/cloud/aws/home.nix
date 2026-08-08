{
  features.cloud-aws.homeManager =
    { lib, pkgs, ... }:
    let
      profiles = {
        "profile nagase" = {
          region = "ap-northeast-1";
          output = "json";
          credential_process = "aws configure export-credentials --profile nagase --format process";
        };
      };
      loginProfiles = lib.mapAttrs (_: value: removeAttrs value [ "credential_process" ]) profiles;
      baselineFile = pkgs.writeText "aws-config-baseline" (lib.generators.toINI { } profiles);
      loginConfigFile = pkgs.writeText "aws-config-login" (lib.generators.toINI { } loginProfiles);
      configHelper = pkgs.callPackage ./_packages/config-helper { };
      awsLoginWrapper = pkgs.dotfilesPackages.aws.mkLoginPackage { inherit loginConfigFile; };
      awsConfigReconcile = pkgs.callPackage ./_packages/reconcile-package.nix {
        inherit baselineFile configHelper;
        managedSections = lib.attrNames profiles;
      };
    in
    {
      home.packages = [
        pkgs.awscli2
        awsLoginWrapper
      ];

      # Keep mutable login_session values while reconciling the declarative
      # baseline with the same lock and atomic publish protocol as `aws login`.
      home.activation.awsConfigMerge = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run ${lib.getExe awsConfigReconcile}
      '';
    };
}
