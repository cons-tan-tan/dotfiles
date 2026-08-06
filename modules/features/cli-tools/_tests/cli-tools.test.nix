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
}
