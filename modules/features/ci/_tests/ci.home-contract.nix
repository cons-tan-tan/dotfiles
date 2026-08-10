{ }:
{
  describe =
    target:
    let
      inherit (target) config pkgs;
      hasPackage = package: builtins.elem package config.home.packages;
    in
    {
      ghaDiag = hasPackage pkgs.dotfilesPackages.gha-diag;
      pinact = hasPackage pkgs.pinact;
      zizmor = hasPackage pkgs.dotfilesPackages.zizmor;
    };
  expected = _: {
    ghaDiag = true;
    pinact = true;
    zizmor = true;
  };
}
