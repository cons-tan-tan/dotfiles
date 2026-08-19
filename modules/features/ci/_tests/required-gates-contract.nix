{
  checks,
  lib,
  pkgs,
}:
let
  requiredChecks = {
    aarch64-darwin = [
      "check-flake-file"
      "darwin-system"
      "treefmt"
    ];
    aarch64-linux = [
      "nixos-wsl-system"
      "reuse-lint"
      "treefmt"
    ];
    x86_64-linux = [
      "dendritic-module-boundary-tests"
      "flake-public-api-contract"
      "home-feature-contract"
      "platform-feature-contract"
      "reuse-lint"
      "rust-tests"
      "test-discovery-tests"
      "treefmt"
      "windows-class-contract"
      "workflow-policy-tests"
    ];
  };
  missingChecks = lib.mapAttrs (
    system: names: builtins.filter (name: !(builtins.hasAttr name checks.${system})) names
  ) requiredChecks;
  expectedFlakeFileTargets = {
    aarch64-darwin = "repo-quality";
    x86_64-linux = "repo-quality";
  };
  invalidFlakeFileTargets = builtins.filter (
    system:
    (checks.${system}.check-flake-file.meta.dotfiles.hestia.targets or null) != expectedFlakeFileTargets
  ) (builtins.attrNames expectedFlakeFileTargets);
in
assert lib.assertMsg (lib.all (names: names == [ ]) (builtins.attrValues missingChecks)) ''
  Required CI checks are missing: ${builtins.toJSON missingChecks}
'';
assert lib.assertMsg (invalidFlakeFileTargets == [ ]) ''
  check-flake-file has invalid Hestia targets on: ${builtins.toJSON invalidFlakeFileTargets}
'';
pkgs.runCommand "ci-required-gates-contract" { } ''
  touch "$out"
''
