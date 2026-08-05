{ }:
{
  describe =
    target:
    let
      inherit (target) config pkgs;
      extensions = config.programs.gh.extensions;
    in
    {
      enabled = config.programs.gh.enable;
      apiGet = builtins.elem pkgs.dotfilesPackages.gh-api-get extensions;
      do = builtins.elem pkgs.gh-do extensions;
      poi = builtins.elem pkgs.gh-poi extensions;
    };
  expected = _: {
    enabled = true;
    apiGet = true;
    do = true;
    poi = true;
  };
}
