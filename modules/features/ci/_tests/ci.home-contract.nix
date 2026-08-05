{ }:
{
  describe =
    target:
    let
      inherit (target) config pkgs;
      hasPackage = package: builtins.elem package config.home.packages;
    in
    builtins.all hasPackage [
      pkgs.pinact
      pkgs.zizmor
      pkgs.dotfilesPackages.gha-lint
    ];
  expected = _: true;
}
