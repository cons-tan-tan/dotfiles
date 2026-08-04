{
  homeManager,
  lib,
  pkgs,
}:
let
  contextModule = (import ../context.nix { inherit lib; }).features.platform-context.homeManager;
  nhModule = (import ../nh.nix { }).features.platform-nh.homeManager;
  evaluate =
    {
      cleanupOwner,
      osConfig,
    }:
    (homeManager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = { inherit osConfig; };
      modules = [
        contextModule
        nhModule
        {
          dotfiles.platform = {
            environment = "linux";
            source = "/source/test";
            standalone = cleanupOwner == "home-manager";
            nhCleanupOwner = cleanupOwner;
          };
          home = {
            username = "test";
            homeDirectory = "/home/test";
            stateVersion = "25.11";
          };
        }
      ];
    }).config;
  standaloneWithOsConfig = evaluate {
    cleanupOwner = "home-manager";
    osConfig = { };
  };
  integratedWithoutOsConfig = evaluate {
    cleanupOwner = "nixos";
    osConfig = null;
  };
in
if !pkgs.stdenv.hostPlatform.isLinux then
  {
    testLinuxOnly = {
      expr = true;
      expected = true;
    };
  }
else
  {
    testCleanupOwnershipDoesNotDependOnOsConfigPresence = {
      expr = {
        standaloneWithOsConfig = {
          clean = standaloneWithOsConfig.programs.nh.clean.enable;
          service = standaloneWithOsConfig.systemd.user.services ? nh-clean;
          resultRoots = standaloneWithOsConfig.systemd.user.services ? nh-clean-result-roots;
        };
        integratedWithoutOsConfig = {
          clean = integratedWithoutOsConfig.programs.nh.clean.enable;
          service = integratedWithoutOsConfig.systemd.user.services ? nh-clean;
          resultRoots = integratedWithoutOsConfig.systemd.user.services ? nh-clean-result-roots;
        };
      };
      expected = {
        standaloneWithOsConfig = {
          clean = true;
          service = true;
          resultRoots = true;
        };
        integratedWithoutOsConfig = {
          clean = false;
          service = false;
          resultRoots = false;
        };
      };
    };
  }
