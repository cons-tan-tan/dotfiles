{
  lib,
}:
{
  describe =
    target:
    let
      inherit (target) config pkgs;
      packages = config.home.packages;
      activation = config.home.activation.awsConfigMerge;
    in
    {
      afterWriteBoundary = activation.after == [ "writeBoundary" ];
      usesRun = lib.hasPrefix "run " activation.data;
      reconcilesConfig = lib.hasInfix "aws-config-reconcile" activation.data;
      package = builtins.elem pkgs.awscli2 packages;
      login = builtins.any (package: lib.getName package == "aws-login") packages;
    };
  expected = _: {
    afterWriteBoundary = true;
    usesRun = true;
    reconcilesConfig = true;
    package = true;
    login = true;
  };
}
