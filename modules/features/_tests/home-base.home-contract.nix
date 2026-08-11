{ }:
{
  describe =
    target:
    let
      config = target.config;
    in
    {
      stateVersion = config.home.stateVersion;
      releaseCheck = config.home.enableNixpkgsReleaseCheck;
      homeManager = config.programs.home-manager.enable;
    };
  expected = _: {
    stateVersion = "24.11";
    releaseCheck = true;
    homeManager = true;
  };
}
