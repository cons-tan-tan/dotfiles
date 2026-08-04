_: {
  features.platform-nix-settings = {
    name = "feature/platform/nix-settings";
    nixos =
      { config, lib, ... }:
      {
        nix.settings =
          (import ../../../../nix/lib/nix-custom-settings.nix {
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
