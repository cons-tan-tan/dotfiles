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
      managedPaths = builtins.filter (lib.hasPrefix ".ssh/") (builtins.attrNames config.home.file);
      configIncludesFragments =
        lib.hasInfix "Include ~/.ssh/config.d/*.conf"
          config.home.file.".ssh/config".text;
    };
  expected = _: {
    managedPaths = [
      ".ssh/config"
      ".ssh/config.d/10-common.conf"
    ];
    configIncludesFragments = true;
  };
}
