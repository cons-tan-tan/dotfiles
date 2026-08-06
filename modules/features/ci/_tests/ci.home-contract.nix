{ }:
{
  describe =
    target:
    let
      inherit (target) config pkgs;
      hasPackage = package: builtins.elem package config.home.packages;
    in
    {
      ghaLint = hasPackage pkgs.dotfilesPackages.gha-lint;
      pinact = hasPackage pkgs.pinact;
      zizmor = hasPackage pkgs.zizmor;
    };
  expected = _: {
    ghaLint = true;
    pinact = true;
    zizmor = true;
  };
}
