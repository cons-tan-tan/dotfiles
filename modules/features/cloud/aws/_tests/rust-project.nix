{ ciCheck, pkgs }:
let
  package = pkgs.callPackage ../_packages/config-helper { };
in
{
  name = "aws-config-helper";
  manifest = "modules/features/cloud/aws/_packages/config-helper/Cargo.toml";
  ciTargets = ciCheck.targets.both "rust-and-bats";
  platformPredicate = _platform: true;
  advisoryOnly = false;
  lock = {
    owner = "aws-config-helper";
    path = "modules/features/cloud/aws/_packages/config-helper/Cargo.lock";
    ignoredAdvisories = [ ];
  };
  packages.default = package;
  buildVariants = [
    {
      name = "default";
      checkName = "aws-config-helper-rust";
      inherit package;
    }
  ];
  clippyVariants = [
    {
      name = "default";
      checkName = "aws-config-helper";
      inherit package;
      clippyFlags = [
        "--all-targets"
        "--all-features"
      ];
    }
  ];
}
