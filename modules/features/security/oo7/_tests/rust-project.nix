{ ciCheck, pkgs }:
let
  package = pkgs.dotfilesPackages.oo7-dpapi-bridge;
in
{
  name = "oo7-dpapi-bridge";
  manifest = "modules/features/security/oo7/_packages/oo7-dpapi-bridge/Cargo.toml";
  ciTargets = ciCheck.targets.linux "rust-and-bats";
  platformPredicate = platform: platform.isLinux;
  advisoryOnly = false;
  lock = {
    owner = "oo7-dpapi-bridge";
    path = "modules/features/security/oo7/_packages/oo7-dpapi-bridge/Cargo.lock";
    ignoredAdvisories = [ ];
  };
  packages.default = package;
  subjects.oo7DpapiBridge = package;
  buildVariants = [
    {
      name = "default";
      checkName = "oo7-dpapi-bridge-rust";
      inherit package;
    }
  ];
  clippyVariants = [
    {
      name = "default";
      checkName = "oo7-dpapi-bridge";
      inherit package;
      clippyFlags = [
        "--all-targets"
        "--all-features"
      ];
    }
  ];
}
