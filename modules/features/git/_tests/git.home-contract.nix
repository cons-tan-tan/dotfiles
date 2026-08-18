{ lib }:
{
  describe =
    target:
    let
      inherit (target) config pkgs;
      countPackage =
        package: builtins.length (builtins.filter (candidate: candidate == package) config.home.packages);
      sshenc = lib.findFirst (package: lib.getName package == "sshenc") null config.home.packages;
    in
    {
      enabled = config.programs.git.enable;
      signing = {
        inherit (config.programs.git.signing)
          format
          key
          signByDefault
          ;
        sshencSigner = sshenc != null && config.programs.git.signing.signer == "${sshenc}/bin/sshenc";
      };
      settings = {
        autocrlf = config.programs.git.settings.core.autocrlf;
        defaultBranch = config.programs.git.settings.init.defaultBranch;
        editor = config.programs.git.settings.core.editor;
        worktreeBase = config.programs.git.settings.wt.basedir;
      };
      ignoresLocalClaude = builtins.elem "CLAUDE.local.md" config.programs.git.ignores;
      gitCliff = countPackage pkgs.git-cliff;
    };
  expected = facts: {
    enabled = true;
    signing =
      if facts.environment == "wsl" && !facts.standalone then
        {
          format = "ssh";
          key = "~/.ssh/git-signing.pub";
          signByDefault = true;
          sshencSigner = true;
        }
      else
        {
          format = "openpgp";
          key = "6250E02A31E09AFE";
          signByDefault = true;
          sshencSigner = false;
        };
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
