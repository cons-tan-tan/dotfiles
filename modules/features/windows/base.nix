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
        platform = config.dotfiles.platform;
        deploy = import ./_interface/deploy.nix { inherit lib pkgs; };
        standardResources = cfg.deployments;
        staticResources = cfg.staticResources;
        allResources =
          lib.mapAttrs' (owner: resource: lib.nameValuePair "deployments/${owner}" resource) standardResources
          // lib.mapAttrs' (owner: resource: lib.nameValuePair "static/${owner}" resource) staticResources;
        resourceValidation = deploy.validateResources allResources;
      in
      {
        options.dotfiles.windows = lib.mkOption {
          internal = true;
          default = { };
          description = "Resources and deployment state for the WSL-owned Windows companion.";
          type = lib.types.submodule {
            options = {
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

        config = lib.mkIf platform.windows.enable {
          home.activation =
            lib.optionalAttrs (standardResources != { }) {
              deployWindowsCompanion = deploy.mkActivation {
                after = [ "writeBoundary" ];
                name = "files";
                root = platform.windows.homedir;
                resources = builtins.seq resourceValidation standardResources;
              };
            }
            // lib.optionalAttrs (staticResources != { }) {
              deployWindowsCompanionStatic = deploy.mkActivation {
                after = [ "linkGeneration" ];
                name = "static";
                root = platform.windows.homedir;
                resources = builtins.seq resourceValidation staticResources;
              };
            };
        };
      };
  };
}
