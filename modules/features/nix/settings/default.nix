{
  config,
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
      targets = config.dotfiles.targets.${system};
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

  flake.modules.nixos.nix-settings-wsl =
    { config, lib, ... }:
    {
      key = "modules/features/nix/settings/default.nix#nixos.nix-settings-wsl";

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

  perSystem =
    { pkgs, system, ... }:
    let
      appSet = appsFor { inherit pkgs system; };
    in
    {
      inherit (appSet) apps;
      dotfiles.appValidationSets = [ appSet.validationsByName ];
    };
}
