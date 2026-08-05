{ }:
{
  describe = target: builtins.elem target.pkgs.curl target.config.home.packages;
  expected = _: true;
}
