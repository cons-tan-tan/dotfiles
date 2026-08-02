{ lib, pkgs }:
let
  allPlatforms = _: true;
  darwinOnly = platform: platform.isDarwin;
  allTargetsAndFeatures = [
    "--all-targets"
    "--all-features"
  ];

  applyNixSettings = pkgs.callPackage ../apps/apply-nix-settings { };
  applySecrets = pkgs.callPackage ../apps/apply-secrets { };
  updatePins = pkgs.callPackage ../apps/update-pins { };
  updatePinsSmoke = pkgs.callPackage ../apps/update-pins/smoke.nix { };
  agentConfigHelper = pkgs.callPackage ../libexec/agent-config-helper { };
  agentCommandGuard = pkgs.dotfilesPackages.agent-command-guard;
  awsConfigHelper = pkgs.callPackage ../packages/aws/config-helper { };
  safeFetch = pkgs.callPackage ../packages/safe-fetch { };
  sleepctl = pkgs.callPackage ../packages/sleepctl { };

  safeFetchCheck = pkgs.linkFarm "safe-fetch-rust" [
    {
      name = "core";
      path = safeFetch.core;
    }
    {
      name = "curl-fetch";
      path = pkgs.dotfilesPackages.curl-fetch;
    }
    {
      name = "gh-api-get";
      path = pkgs.dotfilesPackages.gh-api-get;
    }
  ];

  mkProject =
    {
      name,
      manifest,
      lockfile,
      package,
      checkName ? "${name}-rust",
      clippyFlags ? allTargetsAndFeatures,
      platformPredicate ? allPlatforms,
    }:
    {
      inherit
        name
        manifest
        platformPredicate
        ;
      advisoryOnly = false;
      lock = {
        owner = name;
        path = lockfile;
        ignoredAdvisories = [ ];
      };
      packages.default = package;
      buildVariants = [
        {
          inherit checkName package;
          name = "default";
        }
      ];
      clippyVariants = [
        {
          inherit clippyFlags;
          name = "default";
          checkName = name;
          package = package;
        }
      ];
    };

  difference = left: right: builtins.filter (value: !(builtins.elem value right)) left;
  duplicates =
    values:
    builtins.filter (
      value: builtins.length (builtins.filter (candidate: candidate == value) values) > 1
    ) (lib.unique values);
  inventoryDiff = discovered: declared: {
    missing = difference discovered declared;
    stale = difference declared discovered;
    duplicate = duplicates declared;
  };
  inventory =
    {
      discoveredManifests,
      discoveredLockfiles,
      projectList ? projects,
    }:
    let
      declaredManifests = builtins.filter (path: path != null) (
        map (project: project.manifest) projectList
      );
      declaredLockfiles = map (project: project.lock.path) projectList;
    in
    {
      manifests = inventoryDiff discoveredManifests declaredManifests;
      lockfiles = inventoryDiff discoveredLockfiles declaredLockfiles;
    };

  projects = [
    (mkProject {
      name = "apply-nix-settings";
      manifest = "apps/apply-nix-settings/Cargo.toml";
      lockfile = "apps/apply-nix-settings/Cargo.lock";
      package = applyNixSettings;
    })
    (mkProject {
      name = "apply-secrets";
      manifest = "apps/apply-secrets/Cargo.toml";
      lockfile = "apps/apply-secrets/Cargo.lock";
      package = applySecrets;
    })
    {
      name = "update-pins";
      manifest = "apps/update-pins/Cargo.toml";
      platformPredicate = allPlatforms;
      advisoryOnly = false;
      lock = {
        owner = "update-pins";
        path = "apps/update-pins/Cargo.lock";
        ignoredAdvisories = [ ];
      };
      packages = {
        default = updatePins;
        smoke = updatePinsSmoke;
      };
      buildVariants = [
        {
          name = "default";
          checkName = "update-pins-rust";
          package = updatePins;
        }
        {
          name = "smoke";
          checkName = "update-pins-smoke";
          package = updatePinsSmoke;
        }
      ];
      clippyVariants = [
        {
          name = "default";
          checkName = "update-pins";
          package = updatePins;
          clippyFlags = [
            "--all-targets"
            "--features"
            "smoke"
          ];
        }
        {
          name = "smoke";
          checkName = "update-pins-smoke";
          package = updatePinsSmoke;
          clippyFlags = [
            "--all-targets"
            "--no-default-features"
            "--features"
            "smoke"
          ];
        }
      ];
    }
    (mkProject {
      name = "agent-config-helper";
      manifest = "libexec/agent-config-helper/Cargo.toml";
      lockfile = "libexec/agent-config-helper/Cargo.lock";
      package = agentConfigHelper;
    })
    (mkProject {
      name = "agent-command-guard";
      manifest = "packages/agent-command-guard/Cargo.toml";
      lockfile = "packages/agent-command-guard/Cargo.lock";
      package = agentCommandGuard;
    })
    (mkProject {
      name = "aws-config-helper";
      manifest = "packages/aws/config-helper/Cargo.toml";
      lockfile = "packages/aws/config-helper/Cargo.lock";
      package = awsConfigHelper;
    })
    {
      name = "safe-fetch";
      manifest = "packages/safe-fetch/Cargo.toml";
      platformPredicate = allPlatforms;
      advisoryOnly = false;
      lock = {
        owner = "safe-fetch";
        path = "packages/safe-fetch/Cargo.lock";
        ignoredAdvisories = [ ];
      };
      packages = safeFetch // {
        check = safeFetchCheck;
      };
      buildVariants = [
        {
          name = "default";
          checkName = "safe-fetch-rust";
          package = safeFetchCheck;
        }
      ];
      clippyVariants = [
        {
          name = "default";
          checkName = "safe-fetch";
          package = safeFetch.core;
          clippyFlags = allTargetsAndFeatures;
        }
      ];
    }
    (mkProject {
      name = "sleepctl";
      manifest = "packages/sleepctl/Cargo.toml";
      lockfile = "packages/sleepctl/Cargo.lock";
      package = sleepctl;
      platformPredicate = darwinOnly;
      clippyFlags = [ "--all-targets" ];
    })
    {
      # shellfirm is built from an upstream source, but its vendored lockfile is
      # kept here so the same reproducible RustSec gate covers the dependency set.
      name = "shellfirm";
      manifest = null;
      platformPredicate = allPlatforms;
      advisoryOnly = true;
      lock = {
        owner = "shellfirm";
        path = "packages/shellfirm/Cargo.lock";
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
  ];
in
{
  inherit
    duplicates
    inventory
    inventoryDiff
    projects
    ;
}
