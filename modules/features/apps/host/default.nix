{
  config,
  den,
  inputs,
  lib,
  ...
}:
let
  configurationTargets = import ../../../flake/_interface/configuration-targets.nix {
    inherit lib;
  };
  nhPackageSources = import ../../platform/nh/_interface/package-sources.nix;
  appsFor =
    { pkgs, ... }:
    let
      appSet = import ../_interface/app-set.nix { lib = pkgs.lib; };
      system = pkgs.stdenv.hostPlatform.system;
    in
    if lib.hasSuffix "-darwin" system then
      let
        targets = configurationTargets { inherit den system; };
        darwinConfiguration = config.flake.darwinConfigurations.${targets.darwin};
        darwinAppsFor = import ./_interface/darwin-apps.nix {
          inherit appSet;
          darwinHostname = targets.darwin;
        };
      in
      darwinAppsFor {
        inherit pkgs;
        darwinRebuildBin = "${darwinConfiguration.config.system.build.darwin-rebuild}/bin/darwin-rebuild";
      }
    else
      let
        targets = configurationTargets { inherit den system; };
        nixosConfiguration = config.flake.nixosConfigurations.${targets.nixosWsl};
        mkLinuxApps = import ./_interface/linux-apps.nix {
          inherit appSet inputs;
          homedir = targets.linuxHomedir;
          nhCleanupSystemdSource = nhPackageSources.cleanupSystemd;
          username = targets.username;
          windowsHomedir = targets.windows.homedir;
        };
      in
      assert config.flake.homeConfigurations ? ${targets.home.linux};
      assert config.flake.homeConfigurations ? ${targets.home.wsl};
      mkLinuxApps {
        inherit pkgs system;
        homeTargets = targets.home;
        nixosTarget = targets.nixosWsl;
        nixosRebuildBin = "${nixosConfiguration.config.system.build.nixos-rebuild}/bin/nixos-rebuild";
      };
in
{
  den.aspects.host-apps = {
    apps = args: (appsFor args).apps;
    app-validations = [
      {
        produce = args: (appsFor args).validationsByName;
      }
    ];
  };

  den.schema.flake-parts.includes = [ den.aspects.host-apps ];
}
