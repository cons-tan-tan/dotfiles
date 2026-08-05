{
  lib,
  standaloneLinux,
  standaloneLinuxResult,
}:
{
  actual = lib.elem standaloneLinuxResult.pkgs.dotfilesPackages.drawio-headless standaloneLinux.home.packages;
  expected = true;
}
