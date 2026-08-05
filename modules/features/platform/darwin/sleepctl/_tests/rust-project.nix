{ ciCheck, pkgs }:
let
  package = pkgs.callPackage ../_packages/sleepctl { };
in
{
  name = "sleepctl";
  manifest = "modules/features/platform/darwin/sleepctl/_packages/sleepctl/Cargo.toml";
  ciTargets = ciCheck.targets.darwin "rust-and-bats";
  platformPredicate = platform: platform.isDarwin;
  advisoryOnly = false;
  lock = {
    owner = "sleepctl";
    path = "modules/features/platform/darwin/sleepctl/_packages/sleepctl/Cargo.lock";
    ignoredAdvisories = [ ];
  };
  packages.default = package;
  subjects = { };
  buildVariants = [
    {
      name = "default";
      checkName = "sleepctl-rust";
      inherit package;
    }
  ];
  clippyVariants = [
    {
      name = "default";
      checkName = "sleepctl";
      inherit package;
      clippyFlags = [ "--all-targets" ];
    }
  ];
}
