{ lib, pkgs }:
let
  aggregate = import ../_lib/aggregate.nix { inherit lib pkgs; };
  entries = [
    {
      id = "nix-only";
      nix = {
        route = "home-packages";
        nixpkgsAttr = "reuse";
      };
    }
    {
      id = "windows-only";
      winget.packageId = "Example.WindowsOnly";
    }
    {
      id = "both";
      nix = {
        route = "home-packages";
        nixpkgsAttr = "ripgrep";
      };
      winget = {
        packageId = "Example.Both";
        dependsOn = [ "windows-only" ];
      };
    }
    # Reaching the same named aspect through two variants is idempotent.
    {
      id = "both";
      nix = {
        route = "home-packages";
        nixpkgsAttr = "ripgrep";
      };
      winget = {
        packageId = "Example.Both";
        dependsOn = [ "windows-only" ];
      };
    }
  ];
  result = aggregate entries;
  rejects = candidate: !(builtins.tryEval (builtins.deepSeq (aggregate candidate) true)).success;
in
{
  testProjectsNixOnlyWindowsOnlyAndSharedResources = {
    expr = {
      ids = map (entry: entry.id) result.checked;
      nixPackages = map lib.getName result.nixHomePackages;
      wingetIds = map (entry: entry.id) result.winget;
    };
    expected = {
      ids = [
        "nix-only"
        "windows-only"
        "both"
      ];
      nixPackages = [
        "reuse"
        "ripgrep"
      ];
      wingetIds = [
        "windows-only"
        "both"
      ];
    };
  };

  testRejectsConflictingDuplicateIds = {
    expr = rejects [
      {
        id = "duplicate";
        winget.packageId = "Example.One";
      }
      {
        id = "duplicate";
        winget.packageId = "Example.Two";
      }
    ];
    expected = true;
  };

  testRejectsDuplicateWingetPackageIds = {
    expr = rejects [
      {
        id = "first";
        winget.packageId = "Example.Duplicate";
      }
      {
        id = "second";
        winget.packageId = "Example.Duplicate";
      }
    ];
    expected = true;
  };

  testRejectsMissingProjection = {
    expr = rejects [ { id = "missing"; } ];
    expected = true;
  };

  testRejectsUnknownFields = {
    expr = rejects [
      {
        id = "unknown";
        winget.packageId = "Example.Unknown";
        surprise = true;
      }
    ];
    expected = true;
  };

  testRejectsInvalidNestedMetadata = {
    expr = rejects [
      {
        id = "invalid-nix";
        nix = {
          route = "home-packages";
          nixpkgsAttr = "does-not-exist";
        };
      }
      {
        id = "invalid-winget";
        winget = {
          packageId = "Example.Invalid";
          elevated = "yes";
        };
      }
    ];
    expected = true;
  };

  testRejectsUnresolvedDependencies = {
    expr = rejects [
      {
        id = "unresolved";
        winget = {
          packageId = "Example.Unresolved";
          dependsOn = [ "missing" ];
        };
      }
    ];
    expected = true;
  };

  testRejectsDependenciesOnNixOnlyEntries = {
    expr = rejects [
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
    expected = true;
  };

  testRejectsSelfDependencies = {
    expr = rejects [
      {
        id = "self";
        winget = {
          packageId = "Example.Self";
          dependsOn = [ "self" ];
        };
      }
    ];
    expected = true;
  };

  testRejectsDependencyCycles = {
    expr = rejects [
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
    expected = true;
  };
}
