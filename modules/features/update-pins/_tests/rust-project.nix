{
  ciCheck,
  pkgs,
}:
let
  package = pkgs.callPackage ../_packages/update-pins { };
  smokePackage = pkgs.callPackage ../_packages/update-pins/smoke.nix { };
in
{
  name = "update-pins";
  manifest = "modules/features/update-pins/_packages/update-pins/Cargo.toml";
  ciTargets = ciCheck.targets.both "rust-and-bats";
  platformPredicate = _platform: true;
  advisoryOnly = false;
  lock = {
    owner = "update-pins";
    path = "modules/features/update-pins/_packages/update-pins/Cargo.lock";
    ignoredAdvisories = [ ];
  };
  packages = {
    default = package;
    smoke = smokePackage;
  };
  buildVariants = [
    {
      name = "default";
      checkName = "update-pins-rust";
      inherit package;
    }
    {
      name = "smoke";
      checkName = "update-pins-smoke";
      package = smokePackage;
    }
  ];
  clippyVariants = [
    {
      name = "default";
      checkName = "update-pins";
      inherit package;
      clippyFlags = [
        "--all-targets"
        "--features"
        "smoke"
      ];
    }
    {
      name = "smoke";
      checkName = "update-pins-smoke";
      package = smokePackage;
      clippyFlags = [
        "--all-targets"
        "--no-default-features"
        "--features"
        "smoke"
      ];
    }
  ];
}
