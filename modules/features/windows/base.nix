{
  flake.modules.homeManager.windows-base = {
    key = "modules/features/windows/base.nix#homeManager.windows-base";
    imports = [
      (
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
        }
      )
    ];
    dotfiles.cliTools = [
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
  };
}
