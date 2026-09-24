{
  flake.modules.homeManager.cloud-gcloud =
    { lib, pkgs, ... }:
    let
      configurations = {
        default.core = { };
        personal.core.account = "zhouchengt@gmail.com";
        tdu.core.account = "makisyu.tdu@gmail.com";
      };
    in
    {
      key = "modules/features/cloud/gcloud.nix#homeManager.cloud-gcloud";

      home.packages = [ pkgs.google-cloud-sdk ];
      xdg.configFile = lib.mapAttrs' (name: settings: {
        name = "gcloud/configurations/config_${name}";
        value.text = lib.generators.toINI { } settings;
      }) configurations;
    };
}
