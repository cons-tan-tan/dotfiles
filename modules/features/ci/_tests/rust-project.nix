{ ciCheck, pkgs }:
let
  package = pkgs.dotfilesPackages.gha-diag;
in
{
  name = "gha-diag";
  manifest = "modules/features/ci/_packages/gha-diag/Cargo.toml";
  ciTargets = ciCheck.targets.both "rust-and-bats";
  platformPredicate = _platform: true;
  advisoryOnly = false;
  lock = {
    owner = "gha-diag";
    path = "modules/features/ci/_packages/gha-diag/Cargo.lock";
    ignoredAdvisories = [ ];
  };
  packages.default = package;
  subjects = { };
  buildVariants = [
    {
      name = "default";
      checkName = "gha-diag-rust";
      inherit package;
    }
  ];
  clippyVariants = [
    {
      name = "default";
      checkName = "gha-diag";
      inherit package;
      clippyFlags = [ "--all-targets" ];
    }
  ];
}
