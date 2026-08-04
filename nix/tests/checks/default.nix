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
    (import ./agent-command-policy.nix {
      inherit
        ciCheck
        currentTargets
        flake
        lib
        pkgs
        subjects
        username
        ;
    })
    (import ./package-smoke.nix {
      inherit ciCheck pkgs repoRoot;
    })
    (import ./repository-quality.nix {
      inherit
        ciCheck
        lib
        pkgs
        repoRoot
        ;
    })
    (import ./nh.nix {
      inherit ciCheck lib pkgs;
    })
  ];
}
