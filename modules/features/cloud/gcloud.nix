{ ... }:
{
  features.cloud-gcloud = {
    name = "feature/cloud/gcloud";
    homeManager =
      { lib, pkgs, ... }:
      let
        configurations = {
          default.core = { };
          personal.core.account = "zhouchengt@gmail.com";
          tdu.core.account = "makisyu.tdu@gmail.com";
        };
      in
      {
        home.packages = [ pkgs.google-cloud-sdk ];
        xdg.configFile = lib.mapAttrs' (name: settings: {
          name = "gcloud/configurations/config_${name}";
          value.text = lib.generators.toINI { } settings;
        }) configurations;
      };
  };
}
