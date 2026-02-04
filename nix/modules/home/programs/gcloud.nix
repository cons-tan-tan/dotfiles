{ pkgs, lib, ... }:
let
  mkGcloudConfig = settings: lib.generators.toINI { } settings;

  configurations = {
    default = {
      core = { };
    };

    personal = {
      core = {
        account = "zhouchengt@gmail.com";
      };
    };
  };
in
{
  home.packages = with pkgs; [
    google-cloud-sdk
  ];

  xdg.configFile = lib.mapAttrs' (name: settings: {
    name = "gcloud/configurations/config_${name}";
    value = {
      text = mkGcloudConfig settings;
    };
  }) configurations;
}
