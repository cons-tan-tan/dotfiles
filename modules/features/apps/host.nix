{
  config,
  den,
  inputs,
  lib,
  ...
}:
let
  username = "constantan";
  darwinHostname = username;
  windowsHomedir = "/mnt/c/Users/zhouc";
  configNames = import ../../../nix/lib/linux-config-name.nix { inherit username; };
  mkDarwinApps = import ../../../nix/lib/apps/mk-darwin-apps.nix { inherit darwinHostname; };
  mkLinuxApps = import ../../../nix/lib/apps/mk-linux-apps.nix {
    inherit inputs username windowsHomedir;
  };
  appsFor =
    { pkgs, system, ... }:
    if lib.hasSuffix "-darwin" system then
      let
        darwinConfiguration = config.flake.darwinConfigurations.${darwinHostname};
      in
      mkDarwinApps {
        inherit pkgs;
        darwinRebuildBin = "${darwinConfiguration.config.system.build.darwin-rebuild}/bin/darwin-rebuild";
      }
    else
      let
        linuxTarget = configNames.forHost {
          hostKind = "linux";
          inherit system;
        };
        wslTarget = configNames.forHost {
          hostKind = "wsl";
          inherit system;
        };
        nixosTarget = configNames.forNixosWsl { inherit system; };
        nixosConfiguration = config.flake.nixosConfigurations.${nixosTarget};
      in
      assert config.flake.homeConfigurations ? ${linuxTarget};
      assert config.flake.homeConfigurations ? ${wslTarget};
      mkLinuxApps {
        inherit nixosTarget pkgs system;
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
