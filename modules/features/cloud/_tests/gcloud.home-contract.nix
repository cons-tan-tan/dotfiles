{ }:
{
  describe =
    target:
    let
      inherit (target) config pkgs;
    in
    {
      package = builtins.elem pkgs.google-cloud-sdk config.home.packages;
      default = config.xdg.configFile."gcloud/configurations/config_default".text;
      personal = config.xdg.configFile."gcloud/configurations/config_personal".text;
      tdu = config.xdg.configFile."gcloud/configurations/config_tdu".text;
    };
  expected = _: {
    package = true;
    default = "[core]\n";
    personal = "[core]\naccount=zhouchengt@gmail.com\n";
    tdu = "[core]\naccount=makisyu.tdu@gmail.com\n";
  };
}
