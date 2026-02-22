{ pkgs, ... }:
{
  programs.starship = {
    enable = true;
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
