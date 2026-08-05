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
      gopass = countPackage pkgs.gopass;
      sops = countPackage pkgs.sops;
      trufflehog = countPackage pkgs.trufflehog;
    };
  expected = _: {
    gopass = 1;
    sops = 1;
    trufflehog = 1;
  };
}
