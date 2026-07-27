{ ... }:
{
  programs.starship = {
    enable = true;
    presets = [ "nerd-font-symbols" ];
    settings = {
      gcloud = {
        detect_env_vars = [ "CLOUDSDK_ACTIVE_CONFIG_NAME" ];
      };
      python = {
        detect_extensions = [ ];
        detect_files = [ ];
      };
    };
  };
}
