{
  den,
  lib,
  ...
}:
let
  mkAppSet = import ./_interface/app-set.nix;
  mkSettings = import ./_interface/custom-settings.nix;
  appsFor =
    {
      pkgs,
      system,
      ...
    }:
    let
      targets = (import ../../../flake/_interface/configuration-targets.nix { inherit lib; }) {
        inherit den system;
      };
    in
    mkAppSet {
      inherit pkgs;
      username = targets.username;
    };
in
{
  den.aspects.apply-nix-settings = {
    apps = args: (appsFor args).apps;
    app-validations = [
      {
        produce = args: (appsFor args).validationsByName;
      }
    ];
  };

  den.schema.flake-parts.includes = [ den.aspects.apply-nix-settings ];

  features.platform-nix-settings = {
    name = "feature/platform/nix-settings";
    nixos =
      { config, lib, ... }:
      {
        nix.settings =
          (mkSettings {
            inherit lib;
            username = config.wsl.defaultUser;
          }).settings
          // {
            experimental-features = [
              "nix-command"
              "flakes"
            ];
          };
      };
  };
}
