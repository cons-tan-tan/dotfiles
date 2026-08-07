{ ciCheck, pkgs }:
let
  package = pkgs.callPackage ../_packages/nix-mutation-test { };
in
{
  name = "nix-mutation-test";
  manifest = "modules/features/devshell/_packages/nix-mutation-test/Cargo.toml";
  ciTargets = ciCheck.targets.both "rust-and-bats";
  platformPredicate = _platform: true;
  advisoryOnly = false;
  lock = {
    owner = "nix-mutation-test";
    path = "modules/features/devshell/_packages/nix-mutation-test/Cargo.lock";
    ignoredAdvisories = [ ];
  };
  packages.default = package;
  subjects.nixMutationTest = package;
  buildVariants = [
    {
      name = "default";
      checkName = "nix-mutation-test-rust";
      inherit package;
    }
  ];
  clippyVariants = [
    {
      name = "default";
      checkName = "nix-mutation-test";
      inherit package;
      clippyFlags = [
        "--all-targets"
        "--all-features"
      ];
    }
  ];
}
