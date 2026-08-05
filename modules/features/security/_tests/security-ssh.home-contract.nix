{
  lib,
}:
{
  describe =
    target:
    let
      config = target.config;
    in
    {
      config = config.home.file ? ".ssh/config";
      common = config.home.file ? ".ssh/config.d/10-common.conf";
      privateAbsent = !(config.home.file ? ".ssh/config.d/50-private.conf");
      configIncludesFragments =
        lib.hasInfix "Include ~/.ssh/config.d/*.conf"
          config.home.file.".ssh/config".text;
      commonHasGithub =
        lib.hasInfix "Host github.com"
          config.home.file.".ssh/config.d/10-common.conf".text;
    };
  expected = _: {
    config = true;
    common = true;
    privateAbsent = true;
    configIncludesFragments = true;
    commonHasGithub = true;
  };
}
