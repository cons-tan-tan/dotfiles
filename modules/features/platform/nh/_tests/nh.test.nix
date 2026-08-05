{
  homeManager,
  lib,
  pkgs,
}:
let
  contextModule = (import ../../context.nix { inherit lib; }).features.platform-context.homeManager;
  nhModule =
    (import ../default.nix {
      features.platform-nh = "platform-nh";
    }).features.platform-nh.homeManager;
  evaluate =
    {
      environment,
      osConfig,
      standalone,
    }:
    (homeManager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = { inherit osConfig; };
      modules = [
        contextModule
        nhModule
        {
          dotfiles.platform = {
            inherit environment standalone;
            source = "/source/test";
          };
          home = {
            username = "test";
            homeDirectory = "/home/test";
            stateVersion = "25.11";
          };
        }
      ];
    }).config;
  standaloneLinuxWithOsConfig = evaluate {
    environment = "linux";
    osConfig = { };
    standalone = true;
  };
  integratedWslWithoutOsConfig = evaluate {
    environment = "wsl";
    osConfig = null;
    standalone = false;
  };
  standaloneWslWithoutOsConfig = evaluate {
    environment = "wsl";
    osConfig = null;
    standalone = true;
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
        standaloneLinuxWithOsConfig = {
          clean = standaloneLinuxWithOsConfig.programs.nh.clean.enable;
          service = standaloneLinuxWithOsConfig.systemd.user.services ? nh-clean;
          resultRoots = standaloneLinuxWithOsConfig.systemd.user.services ? nh-clean-result-roots;
        };
        integratedWslWithoutOsConfig = {
          clean = integratedWslWithoutOsConfig.programs.nh.clean.enable;
          service = integratedWslWithoutOsConfig.systemd.user.services ? nh-clean;
          resultRoots = integratedWslWithoutOsConfig.systemd.user.services ? nh-clean-result-roots;
        };
        standaloneWslWithoutOsConfig = {
          clean = standaloneWslWithoutOsConfig.programs.nh.clean.enable;
          service = standaloneWslWithoutOsConfig.systemd.user.services ? nh-clean;
          resultRoots = standaloneWslWithoutOsConfig.systemd.user.services ? nh-clean-result-roots;
        };
      };
      expected = {
        standaloneLinuxWithOsConfig = {
          clean = true;
          service = true;
          resultRoots = true;
        };
        integratedWslWithoutOsConfig = {
          clean = false;
          service = false;
          resultRoots = false;
        };
        standaloneWslWithoutOsConfig = {
          clean = false;
          service = false;
          resultRoots = false;
        };
      };
    };
  }
