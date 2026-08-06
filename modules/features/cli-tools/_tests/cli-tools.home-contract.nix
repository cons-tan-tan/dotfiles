{ }:
{
  describe =
    target:
    let
      inherit (target) config pkgs;
      hasPackage = package: builtins.elem package config.home.packages;
    in
    {
      astGrep = hasPackage pkgs.ast-grep;
      bat = hasPackage pkgs.bat;
      eza = hasPackage pkgs.eza;
      fd = hasPackage pkgs.fd;
      fzf = hasPackage pkgs.fzf;
      jq = hasPackage pkgs.jq;
      reuse = hasPackage pkgs.reuse;
      ripgrep = hasPackage pkgs.ripgrep;
    };
  expected = _: {
    astGrep = true;
    bat = true;
    eza = true;
    fd = true;
    fzf = true;
    jq = true;
    reuse = true;
    ripgrep = true;
  };
}
