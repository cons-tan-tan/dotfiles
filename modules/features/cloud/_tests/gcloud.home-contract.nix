{ }:
{
  describe =
    target:
    let
      inherit (target) config pkgs;
    in
    {
      package = builtins.elem pkgs.google-cloud-sdk config.home.packages;
      default = config.xdg.configFile."gcloud/configurations/config_default".text == "[core]\n";
      personal =
        config.xdg.configFile."gcloud/configurations/config_personal".text
        == "[core]\naccount=zhouchengt@gmail.com\n";
      tdu =
        config.xdg.configFile."gcloud/configurations/config_tdu".text
        == "[core]\naccount=makisyu.tdu@gmail.com\n";
    };
  expected = _: {
    package = true;
    default = true;
    personal = true;
    tdu = true;
  };
}
