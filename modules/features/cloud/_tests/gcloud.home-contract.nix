{ }:
{
  describe =
    target:
    let
      inherit (target) config;
    in
    {
      default = config.xdg.configFile."gcloud/configurations/config_default".text;
      personal = config.xdg.configFile."gcloud/configurations/config_personal".text;
      tdu = config.xdg.configFile."gcloud/configurations/config_tdu".text;
    };
  expected = _: {
    default = "[core]\n";
    personal = "[core]\naccount=zhouchengt@gmail.com\n";
    tdu = "[core]\naccount=makisyu.tdu@gmail.com\n";
  };
}
