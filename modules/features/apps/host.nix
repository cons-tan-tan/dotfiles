{
  config,
  den,
  inputs,
  lib,
  ...
}:
let
  username = "constantan";
  linuxHomedir = "/home/${username}";
  configurationTargets = import ../../entities/_lib/configuration-targets.nix { inherit lib; };
  appsFor =
    { pkgs, system, ... }:
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
        windowsHomedir = den.homes.${system}.${targets.entityNames.home.wsl}.dotfiles.windows.homedir;
        mkLinuxApps = import ../../../nix/lib/apps/mk-linux-apps.nix {
          inherit inputs username windowsHomedir;
          homedir = linuxHomedir;
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
  scriptNamesFor =
    system:
    [
      "build"
      "switch"
    ]
    ++ lib.optional (lib.hasSuffix "-linux" system) "apply-winget";
  mkScriptEntry = name: {
    inherit name;
    mkDerivation = args: (appsFor args).scriptsByName.${name};
  };
in
{
  den.aspects.host-apps = {
    apps = args: (appsFor args).apps;
    app-scripts =
      { system, ... }:
      map mkScriptEntry (scriptNamesFor system);
  };

  den.schema.flake-parts.includes = [ den.aspects.host-apps ];
}
