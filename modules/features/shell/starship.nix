{
  flake.modules.homeManager.shell-starship = {
    key = "modules/features/shell/starship.nix#homeManager.shell-starship";
    imports = [
      {
        programs.starship = {
          enable = true;
          presets = [ "nerd-font-symbols" ];
          settings = {
            gcloud.detect_env_vars = [ "CLOUDSDK_ACTIVE_CONFIG_NAME" ];
            python = {
              detect_extensions = [ ];
              detect_files = [ ];
            };
          };
        };
      }
    ];
    dotfiles.cliTools = [
      {
        id = "starship";
        nix.route = "programs";
        winget = {
          packageId = "Starship.Starship";
          description = "Starship";
        };
      }
    ];
  };
}
