{
  ciCheck,
  currentTargets,
  flake,
  lib,
  pkgs,
  repoRoot,
  subjects,
  username,
}:
{
  producers = [
    (import ../../../agents/base/_tests/command-policy-checks.nix {
      inherit
        ciCheck
        currentTargets
        flake
        lib
        pkgs
        subjects
        username
        ;
      piExtensionSource =
        repoRoot + "/modules/features/agents/pi/_data/extensions/agent-command-guard.ts";
    })
    (import ./package-smoke.nix {
      inherit ciCheck lib pkgs;
    })
    (import ../../_tests/repository-quality.nix {
      inherit
        ciCheck
        lib
        pkgs
        repoRoot
        ;
    })
    (import ../../../platform/nh/_tests/package-checks.nix {
      inherit ciCheck lib pkgs;
    })
  ];
}
