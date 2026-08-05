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
      comma = config.programs.nix-index-database.comma.enable;
    };
  expected = _: {
    stateVersion = "24.11";
    releaseCheck = true;
    homeManager = true;
    comma = true;
  };
}
