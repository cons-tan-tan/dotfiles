{ lib, ... }:
{
  features.platform-context = {
    name = "feature/platform/context";
    homeManager =
      { config, ... }:
      let
        platform = config.dotfiles.platform;
        windows = platform.windows;
      in
      {
        options.dotfiles.platform = lib.mkOption {
          internal = true;
          description = "Canonical Den identity and environment context for Home Manager features.";
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
              windows = lib.mkOption {
                default = { };
                type = lib.types.submodule {
                  options = {
                    enable = lib.mkOption {
                      type = lib.types.bool;
                      default = false;
                    };
                    username = lib.mkOption {
                      type = lib.types.nullOr lib.types.str;
                      default = null;
                    };
                    homedir = lib.mkOption {
                      type = lib.types.nullOr lib.types.str;
                      default = null;
                    };
                  };
                };
              };
            };
          };
        };

        config.assertions = [
          {
            assertion = platform.source != "";
            message = "dotfiles.platform.source must be a non-empty path";
          }
          {
            assertion = !windows.enable || platform.environment == "wsl";
            message = "dotfiles.platform.windows.enable requires dotfiles.platform.environment = wsl";
          }
          {
            assertion = !windows.enable || (windows.username != null && windows.homedir != null);
            message = "dotfiles.platform.windows requires username and homedir when enabled";
          }
          {
            assertion = windows.username == null || windows.username != "";
            message = "dotfiles.platform.windows.username must be non-empty when set";
          }
          {
            assertion = windows.homedir == null || windows.homedir != "";
            message = "dotfiles.platform.windows.homedir must be non-empty when set";
          }
          {
            assertion =
              windows.username == null
              || windows.homedir == null
              || windows.homedir == "/mnt/c/Users/${windows.username}";
            message = "dotfiles.platform.windows.homedir must match dotfiles.platform.windows.username below /mnt/c/Users";
          }
          {
            assertion = windows.enable || (windows.username == null && windows.homedir == null);
            message = "disabled dotfiles.platform.windows identity must be empty";
          }
        ];
      };
  };
}
