{ username }:
{
  describe = target: {
    inherit (target.config.home) homeDirectory username;
    system = target.pkgs.stdenv.hostPlatform.system;
  };
  expected = facts: {
    homeDirectory = facts.homeDirectory;
    inherit username;
    system = facts.system;
  };
}
