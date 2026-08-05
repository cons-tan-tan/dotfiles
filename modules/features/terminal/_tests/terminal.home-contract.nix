{ }:
{
  describe =
    target:
    let
      inherit (target) config pkgs;
      countPackage =
        package: builtins.length (builtins.filter (candidate: candidate == package) config.home.packages);
    in
    {
      fastfetch = countPackage pkgs.fastfetch;
      yazi = countPackage pkgs.yazi;
    };
  expected = _: {
    fastfetch = 1;
    yazi = 1;
  };
}
