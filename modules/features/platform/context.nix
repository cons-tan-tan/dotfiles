{ lib, ... }:
{
  features.platform-context = {
    name = "feature/platform/context";
    homeManager = {
      options.dotfiles.platform = lib.mkOption {
        internal = true;
        description = "Typed Den environment metadata consumed by platform features.";
        type = lib.types.submodule {
          options = {
            environment = lib.mkOption {
              type = lib.types.enum [
                "darwin"
                "linux"
                "wsl"
              ];
            };
            source = lib.mkOption { type = lib.types.str; };
            standalone = lib.mkOption { type = lib.types.bool; };
            windowsCompanion = lib.mkOption {
              type = lib.types.bool;
              default = false;
            };
            nhCleanupOwner = lib.mkOption {
              type = lib.types.enum [
                "home-manager"
                "nixos"
                "none"
                "switch-app"
              ];
            };
          };
        };
      };
    };
  };
}
