{ ciCheck, pkgs }:
let
  package = pkgs.callPackage ../_packages/apply-secrets { };
in
{
  name = "apply-secrets";
  manifest = "modules/features/security/secrets/_packages/apply-secrets/Cargo.toml";
  ciTargets = ciCheck.targets.both "rust-and-bats";
  platformPredicate = _platform: true;
  advisoryOnly = false;
  lock = {
    owner = "apply-secrets";
    path = "modules/features/security/secrets/_packages/apply-secrets/Cargo.lock";
    ignoredAdvisories = [ ];
  };
  packages.default = package;
  buildVariants = [
    {
      name = "default";
      checkName = "apply-secrets-rust";
      inherit package;
    }
  ];
  clippyVariants = [
    {
      name = "default";
      checkName = "apply-secrets";
      inherit package;
      clippyFlags = [
        "--all-targets"
        "--all-features"
      ];
    }
  ];
}
