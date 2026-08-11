{
  lib,
}:
{
  describe = target: {
    package = builtins.elem target.pkgs.git-wt target.config.home.packages;
    zsh = lib.hasInfix "git-wt --init zsh" target.config.programs.zsh.initContent;
  };
  expected = _: {
    package = true;
    zsh = true;
  };
}
