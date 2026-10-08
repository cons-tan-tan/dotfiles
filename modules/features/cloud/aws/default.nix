{
  flake.modules.homeManager.cloud-aws =
    { lib, pkgs, ... }:
    let
      profiles = {
        "profile nagase" = {
          region = "ap-northeast-1";
          output = "json";
        };
      };
      baselineFile = pkgs.writeText "aws-config-baseline" (lib.generators.toINI { } profiles);
      configHelper = pkgs.callPackage ./_packages/config-helper { };
      awsConfigReconcile = pkgs.callPackage ./_packages/reconcile-package.nix {
        inherit baselineFile configHelper;
        managedSections = lib.attrNames profiles;
      };
    in
    {
      key = "modules/features/cloud/aws/default.nix#homeManager.cloud-aws";

      home.packages = [ pkgs.awscli2 ];

      # `aws login` writes login_session, so retain it across activation while
      # restoring the declarative settings in this mutable config file.
      home.activation.awsConfigMerge = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run ${lib.getExe awsConfigReconcile}
      '';
    };
}
