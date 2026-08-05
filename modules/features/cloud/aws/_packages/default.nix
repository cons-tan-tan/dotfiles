{ callPackage }:
{
  mkLoginPackage =
    { loginConfigFile }:
    callPackage ./login-package.nix {
      inherit loginConfigFile;
      configHelper = callPackage ./config-helper { };
    };
}
