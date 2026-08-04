{
  den,
  lib,
  ...
}:
let
  fileType = lib.types.submodule {
    options = {
      source = lib.mkOption { type = lib.types.str; };
      destination = lib.mkOption { type = lib.types.str; };
      mode = lib.mkOption {
        type = lib.types.strMatching "0[0-7]{3}";
        default = "0644";
      };
    };
  };
  treeType = lib.types.submodule {
    options = {
      source = lib.mkOption { type = lib.types.str; };
      destination = lib.mkOption { type = lib.types.str; };
      excludes = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
    };
  };
  resourceType = lib.types.submodule {
    options = {
      directories = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
      files = lib.mkOption {
        type = lib.types.listOf fileType;
        default = [ ];
      };
      trees = lib.mkOption {
        type = lib.types.listOf treeType;
        default = [ ];
      };
    };
  };
in
{
  features.windows-base = {
    name = "feature/windows/base";
    includes = [ den.aspects.windows-forward ];
    cli-tools = [
      {
        id = "op-cli";
        winget = {
          packageId = "AgileBits.1Password.CLI";
          description = "1Password CLI";
        };
      }
      {
        id = "zed";
        winget = {
          packageId = "ZedIndustries.Zed";
          description = "Zed";
        };
      }
      {
        id = "wt";
        winget = {
          packageId = "Microsoft.WindowsTerminal";
          description = "Windows Terminal";
        };
      }
      {
        id = "pwsh";
        winget = {
          packageId = "Microsoft.PowerShell";
          description = "PowerShell 7";
        };
      }
    ];
    homeManager =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        cfg = config.dotfiles.windows;
        deploy = import ./_lib/deploy.nix { inherit lib pkgs; };
        standardResources = builtins.attrValues cfg.deployments;
        staticResources = builtins.attrValues cfg.staticResources;
      in
      {
        options.dotfiles.windows = lib.mkOption {
          internal = true;
          default = { };
          description = "Typed metadata and resources for the WSL-owned Windows companion.";
          type = lib.types.submodule {
            options = {
              enable = lib.mkEnableOption "the Windows companion";
              environment = lib.mkOption {
                type = lib.types.nullOr (lib.types.enum [ "wsl" ]);
                default = null;
              };
              username = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
              };
              homedir = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
              };
              linuxHomedir = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
              };
              source = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
              };
              wingetEnabled = lib.mkOption {
                type = lib.types.bool;
                default = false;
                internal = true;
              };
              deployments = lib.mkOption {
                type = lib.types.attrsOf resourceType;
                default = { };
              };
              staticResources = lib.mkOption {
                type = lib.types.attrsOf resourceType;
                default = { };
              };
            };
          };
        };

        config = lib.mkMerge [
          {
            assertions = [
              {
                assertion = cfg.enable == config.dotfiles.platform.windowsCompanion;
                message = "dotfiles.windows.enable must match dotfiles.platform.windowsCompanion";
              }
              {
                assertion = !cfg.enable || cfg.environment == config.dotfiles.platform.environment;
                message = "dotfiles.windows.environment must match dotfiles.platform.environment";
              }
            ];
          }
          (lib.mkIf cfg.enable {
            assertions = [
              {
                assertion =
                  cfg.environment == "wsl"
                  && cfg.username != null
                  && cfg.homedir != null
                  && cfg.linuxHomedir != null
                  && cfg.source != null;
                message = "dotfiles.windows requires WSL environment, username, homedir, linuxHomedir, and source metadata";
              }
              {
                assertion =
                  cfg.username != null && cfg.homedir != null && cfg.homedir == "/mnt/c/Users/${cfg.username}";
                message = "dotfiles.windows.homedir must match dotfiles.windows.username below /mnt/c/Users";
              }
            ];
            home.activation =
              lib.optionalAttrs (standardResources != [ ]) {
                deployWindowsCompanion = deploy.mkActivation {
                  after = [ "writeBoundary" ];
                  name = "files";
                  root = cfg.homedir;
                  resources = standardResources;
                };
              }
              // lib.optionalAttrs (staticResources != [ ]) {
                deployWindowsCompanionStatic = deploy.mkActivation {
                  after = [ "linkGeneration" ];
                  name = "static";
                  root = cfg.homedir;
                  resources = staticResources;
                };
              };
          })
        ];
      };
  };
}
