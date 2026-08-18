{ ciCheck, pkgs }:
let
  package = pkgs.dotfilesPackages.wsl-dpapi;
  nativeTests = package.tests;
in
{
  name = "wsl-dpapi";
  manifest = "modules/features/security/dpapi/_packages/wsl-dpapi/Cargo.toml";
  ciTargets = ciCheck.targets.linux "rust-and-bats";
  platformPredicate = platform: platform.isLinux;
  advisoryOnly = false;
  lock = {
    owner = "wsl-dpapi";
    path = "modules/features/security/dpapi/_packages/wsl-dpapi/Cargo.lock";
    ignoredAdvisories = [ ];
  };
  packages.default = package;
  subjects.wslDpapi = package;
  buildVariants = [
    {
      name = "windows";
      checkName = "wsl-dpapi-windows-rust";
      inherit package;
    }
    {
      name = "native-tests";
      checkName = "wsl-dpapi-native-tests-rust";
      package = nativeTests;
    }
  ];
  clippyVariants = [
    {
      name = "native-tests";
      checkName = "wsl-dpapi-native-tests";
      package = nativeTests;
      clippyFlags = [ "--all-targets" ];
    }
  ];
}
