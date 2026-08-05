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
      enabled = config.programs.git.enable;
      signingKey = config.programs.git.signing.key;
      signByDefault = config.programs.git.signing.signByDefault;
      settings = {
        autocrlf = config.programs.git.settings.core.autocrlf;
        defaultBranch = config.programs.git.settings.init.defaultBranch;
        editor = config.programs.git.settings.core.editor;
        worktreeBase = config.programs.git.settings.wt.basedir;
      };
      ignoresLocalClaude = builtins.elem "CLAUDE.local.md" config.programs.git.ignores;
      gitCliff = countPackage pkgs.git-cliff;
    };
  expected = _: {
    enabled = true;
    signingKey = "6250E02A31E09AFE";
    signByDefault = true;
    settings = {
      autocrlf = "input";
      defaultBranch = "main";
      editor = "code --wait";
      worktreeBase = ".worktrees";
    };
    ignoresLocalClaude = true;
    gitCliff = 1;
  };
}
