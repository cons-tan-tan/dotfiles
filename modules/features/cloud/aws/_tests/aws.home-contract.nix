{ lib }:
{
  describe =
    target:
    let
      inherit (target) config pkgs;
      packages = config.home.packages;
    in
    {
      activation = config.home.activation ? awsConfigMerge;
      package = builtins.elem pkgs.awscli2 packages;
      login = builtins.any (package: lib.getName package == "aws-login") packages;
    };
  expected = _: {
    activation = true;
    package = true;
    login = true;
  };
}
