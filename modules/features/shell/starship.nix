{
  features.shell-starship = {
    name = "feature/shell/starship";
    cli-tools = [
      {
        id = "starship";
        nix.route = "programs";
        winget = {
          packageId = "Starship.Starship";
          description = "Starship";
        };
      }
    ];
    homeManager.programs.starship = {
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
  };
}
