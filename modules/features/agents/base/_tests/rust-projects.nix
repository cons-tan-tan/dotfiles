{ ciCheck, pkgs }:
let
  packageSources = import ../_interface/package-sources.nix;
  configHelper = pkgs.callPackage packageSources.configHelper { };
  commandGuard = pkgs.dotfilesPackages.agent-command-guard;
  mkProject =
    {
      name,
      manifest,
      lockfile,
      package,
    }:
    {
      inherit name manifest;
      ciTargets = ciCheck.targets.both "rust-and-bats";
      platformPredicate = _platform: true;
      advisoryOnly = false;
      lock = {
        owner = name;
        path = lockfile;
        ignoredAdvisories = [ ];
      };
      packages.default = package;
      buildVariants = [
        {
          name = "default";
          checkName = "${name}-rust";
          inherit package;
        }
      ];
      clippyVariants = [
        {
          name = "default";
          checkName = name;
          inherit package;
          clippyFlags = [
            "--all-targets"
            "--all-features"
          ];
        }
      ];
    };
in
[
  (mkProject {
    name = "agent-config-helper";
    manifest = "modules/features/agents/base/_packages/config-helper/Cargo.toml";
    lockfile = "modules/features/agents/base/_packages/config-helper/Cargo.lock";
    package = configHelper;
  })
  (mkProject {
    name = "agent-command-guard";
    manifest = "modules/features/agents/base/_packages/command-guard/Cargo.toml";
    lockfile = "modules/features/agents/base/_packages/command-guard/Cargo.lock";
    package = commandGuard;
  })
  {
    # shellfirm is built from an upstream source, but its vendored lockfile is
    # kept here so the same reproducible RustSec gate covers the dependency set.
    name = "shellfirm";
    manifest = null;
    ciTargets = ciCheck.targets.both "rust-and-bats";
    platformPredicate = _platform: true;
    advisoryOnly = true;
    lock = {
      owner = "shellfirm";
      path = "modules/features/agents/base/_packages/shellfirm/Cargo.lock";
      ignoredAdvisories = [
        {
          id = "RUSTSEC-2026-0002";
          reviewedAt = "2026-07-24";
          # 2026-11-01T00:00:00Z. ratatui 0.29 is the only lru consumer and
          # does not call the affected LruCache::iter_mut API. Remove this
          # exception when shellfirm upgrades to ratatui with lru >= 0.16.3.
          expiresAt = 1793491200;
        }
      ];
    };
    packages = { };
    buildVariants = [ ];
    clippyVariants = [ ];
  }
]
