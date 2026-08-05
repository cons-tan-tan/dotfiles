{ ciCheck, pkgs }:
let
  package = pkgs.callPackage ../_packages/apply-nix-settings { };
in
{
  name = "apply-nix-settings";
  manifest = "modules/features/platform/nix-settings/_packages/apply-nix-settings/Cargo.toml";
  ciTargets = ciCheck.targets.both "rust-and-bats";
  platformPredicate = _platform: true;
  advisoryOnly = false;
  lock = {
    owner = "apply-nix-settings";
    path = "modules/features/platform/nix-settings/_packages/apply-nix-settings/Cargo.lock";
    ignoredAdvisories = [ ];
  };
  packages.default = package;
  subjects.applyNixSettingsCore = package;
  buildVariants = [
    {
      name = "default";
      checkName = "apply-nix-settings-rust";
      inherit package;
    }
  ];
  clippyVariants = [
    {
      name = "default";
      checkName = "apply-nix-settings";
      inherit package;
      clippyFlags = [
        "--all-targets"
        "--all-features"
      ];
    }
  ];
}
