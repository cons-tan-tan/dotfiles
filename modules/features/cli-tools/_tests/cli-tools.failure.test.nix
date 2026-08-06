{
  caseName,
  nixpkgsPath,
  repoRoot,
}:
let
  lib = import (nixpkgsPath + "/lib");
  fakePackage = name: {
    type = "derivation";
    inherit name;
  };
  pkgs = {
    reuse = fakePackage "reuse";
  };
  aggregate = import (repoRoot + "/modules/features/cli-tools/_lib/aggregate.nix") {
    inherit lib pkgs;
  };
  force = entries: builtins.deepSeq (aggregate entries) true;
  cases = {
    conflictingDuplicateIds = {
      expression = force [
        {
          id = "duplicate";
          winget.packageId = "Example.One";
        }
        {
          id = "duplicate";
          winget.packageId = "Example.Two";
        }
      ];
      expectedFragment = "cli-tools contains duplicate IDs: duplicate";
    };
    duplicateWingetPackageIds = {
      expression = force [
        {
          id = "first";
          winget.packageId = "Example.Duplicate";
        }
        {
          id = "second";
          winget.packageId = "Example.Duplicate";
        }
      ];
      expectedFragment = "cli-tools contains duplicate WinGet package IDs: Example.Duplicate";
    };
    missingProjection = {
      expression = force [ { id = "missing"; } ];
      expectedFragment = "cli-tools.missing must target Nix, WinGet, or both";
    };
    unknownEntryField = {
      expression = force [
        {
          id = "unknown";
          winget.packageId = "Example.Unknown";
          surprise = true;
        }
      ];
      expectedFragment = "cli-tools entry contains unknown fields";
    };
    invalidNixPackage = {
      expression = force [
        {
          id = "invalid-nix";
          nix = {
            route = "home-packages";
            nixpkgsAttr = "does-not-exist";
          };
        }
      ];
      expectedFragment = "cli-tools.invalid-nix.nix.nixpkgsAttr must resolve to a package";
    };
    invalidWingetElevation = {
      expression = force [
        {
          id = "invalid-winget";
          winget = {
            packageId = "Example.Invalid";
            elevated = "yes";
          };
        }
      ];
      expectedFragment = "cli-tools.invalid-winget.winget.elevated must be boolean";
    };
    unresolvedDependency = {
      expression = force [
        {
          id = "unresolved";
          winget = {
            packageId = "Example.Unresolved";
            dependsOn = [ "missing" ];
          };
        }
      ];
      expectedFragment = "cli-tools contains unresolved WinGet dependencies: missing";
    };
    dependencyOnNixOnlyEntry = {
      expression = force [
        {
          id = "nix-only";
          nix = {
            route = "home-packages";
            nixpkgsAttr = "reuse";
          };
        }
        {
          id = "windows";
          winget = {
            packageId = "Example.Windows";
            dependsOn = [ "nix-only" ];
          };
        }
      ];
      expectedFragment = "cli-tools contains unresolved WinGet dependencies: nix-only";
    };
    selfDependency = {
      expression = force [
        {
          id = "self";
          winget = {
            packageId = "Example.Self";
            dependsOn = [ "self" ];
          };
        }
      ];
      expectedFragment = "cli-tools contains self-referencing WinGet dependencies";
    };
    dependencyCycle = {
      expression = force [
        {
          id = "a";
          winget = {
            packageId = "Example.A";
            dependsOn = [ "b" ];
          };
        }
        {
          id = "b";
          winget = {
            packageId = "Example.B";
            dependsOn = [ "a" ];
          };
        }
      ];
      expectedFragment = "cli-tools contains a WinGet dependency cycle: a, b";
    };
  };
in
if caseName == null then cases else cases.${caseName}.expression
