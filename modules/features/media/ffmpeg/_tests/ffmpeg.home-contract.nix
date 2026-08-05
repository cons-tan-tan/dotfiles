{ }:
{
  describe =
    target:
    builtins.length (
      builtins.filter (package: package == target.pkgs.ffmpeg) target.config.home.packages
    );
  expected = _: 1;
}
