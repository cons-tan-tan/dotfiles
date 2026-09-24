{
  config,
  inputs,
  lib,
  ...
}:
let
  nhPackageSources = import ../../nix/lifecycle/_interface/package-sources.nix;
  appsFor =
    { pkgs, ... }:
    let
      appSet = import ../_interface/app-set.nix { lib = pkgs.lib; };
      system = pkgs.stdenv.hostPlatform.system;
    in
    if lib.hasSuffix "-darwin" system then
      let
        targets = config.dotfiles.targets.${system};
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
        targets = config.dotfiles.targets.${system};
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
  perSystem =
    { pkgs, ... }:
    let
      appSet = appsFor { inherit pkgs; };
    in
    {
      inherit (appSet) apps;
      dotfiles.appValidationSets = [ appSet.validationsByName ];
    };
}
