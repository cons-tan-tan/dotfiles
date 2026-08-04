{
  config,
  den,
  inputs,
  lib,
  ...
}:
let
  configurationTargets = import ../../entities/_lib/configuration-targets.nix { inherit lib; };
  appsFor =
    { pkgs, ... }:
    let
      system = pkgs.stdenv.hostPlatform.system;
    in
    if lib.hasSuffix "-darwin" system then
      let
        targets = configurationTargets { inherit den system; };
        darwinConfiguration = config.flake.darwinConfigurations.${targets.darwin};
        darwinAppsFor = import ../../../nix/lib/apps/mk-darwin-apps.nix {
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
        mkLinuxApps = import ../../../nix/lib/apps/mk-linux-apps.nix {
          inherit inputs;
          homedir = targets.linuxHomedir;
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
