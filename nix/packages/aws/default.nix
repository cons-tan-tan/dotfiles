{ callPackage }:
{
  mkLoginPackage =
    { loginConfigFile }:
    callPackage ./login-package.nix {
      inherit loginConfigFile;
    };
}
