{ lib, ... }:
let
  environmentType = lib.types.enum [
    "darwin"
    "linux"
    "wsl"
  ];

  windowsOptions = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether this WSL configuration manages a Windows companion.";
    };
    username = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Windows companion user name.";
    };
    homedir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Windows companion home as seen from WSL.";
    };
  };
  windowsType = lib.types.submodule { options = windowsOptions; };

  environmentOptions = {
    environment = lib.mkOption {
      type = environmentType;
      description = "The project environment represented by this entity.";
    };
    source = lib.mkOption {
      type = lib.types.str;
      description = "The dotfiles source used by the configuration.";
    };
    windows = lib.mkOption {
      type = windowsType;
      default = { };
      description = "Windows companion metadata for WSL configurations.";
    };
  };
  environmentMetadataType = lib.types.submodule { options = environmentOptions; };

  wslAssertion = cfg: {
    assertion =
      cfg.environment != "wsl"
      || (cfg.windows.enable && cfg.windows.username != null && cfg.windows.homedir != null);
    message = "dotfiles.environment = wsl requires an enabled Windows companion with username and homedir";
  };

  hostSchema =
    { config, ... }:
    {
      options.dotfiles = lib.mkOption {
        type = environmentMetadataType;
        description = "Project metadata for this host.";
      };
      config.assertions = [ (wslAssertion config.dotfiles) ];
    };

  userSchema = {
    options.dotfiles = lib.mkOption {
      type = lib.types.submodule {
        options = {
          primary = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Whether this user is the primary user of its host.";
          };
          shell = lib.mkOption {
            type = lib.types.enum [ "zsh" ];
            default = "zsh";
            description = "The shell selected by the user aspect.";
          };
        };
      };
      default = { };
      description = "Project metadata for this user.";
    };
  };

  homeSchema =
    { config, ... }:
    {
      options.dotfiles = lib.mkOption {
        type = lib.types.submodule {
          options = environmentOptions // {
            standalone = lib.mkOption {
              type = lib.types.bool;
              default = true;
              readOnly = true;
              description = "Marks a home entity as standalone rather than OS-integrated.";
            };
          };
        };
        description = "Project metadata for this standalone home.";
      };
      config.assertions = [ (wslAssertion config.dotfiles) ];
    };
in
{
  den.schema.host.imports = [ hostSchema ];
  den.schema.user.imports = [ userSchema ];
  den.schema.home.imports = [ homeSchema ];

  # https://github.com/denful/den/issues/632
  # den.flakeModules.strict still cannot close aspect class keys in the pinned
  # revision. Keep project metadata inside the closed dotfiles submodules above;
  # enable strict only after the existing capability fixture starts passing.
}
