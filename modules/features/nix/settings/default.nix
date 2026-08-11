{
  den,
  lib,
  ...
}:
let
  cache = import ./_data/cache.nix;
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
  flake-file.nixConfig = {
    extra-substituters = [
      "https://cache.nixos.org"
      cache.numtideSubstituter
      cache.nixCommunitySubstituter
    ];
    extra-trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      cache.numtideTrustedPublicKey
      cache.nixCommunityTrustedPublicKey
    ];
  };

  den.aspects.apply-nix-settings = {
    apps = args: (appsFor args).apps;
    app-validations = [
      {
        produce = args: (appsFor args).validationsByName;
      }
    ];
  };

  den.schema.flake-parts.includes = [ den.aspects.apply-nix-settings ];

  features.nix-settings-wsl = {
    name = "feature/nix/settings/wsl";
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
