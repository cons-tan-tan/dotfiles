{ ... }:
{
  describe = target: {
    standardDirenv = target.config.programs.direnv.package == target.pkgs.direnv;
    localSettings = target.config.programs.direnv.stdlib == builtins.readFile ../_scripts/direnvrc.sh;
    ignoresLocal = builtins.elem ".envrc.local" target.config.programs.git.ignores;
    preservesNixDirenv = target.config.programs.direnv.nix-direnv.enable;
  };
  expected = _facts: {
    standardDirenv = true;
    localSettings = true;
    ignoresLocal = true;
    preservesNixDirenv = true;
  };
}
