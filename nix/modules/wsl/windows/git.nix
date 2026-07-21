# Windows companion: Windows 側 git の .gitconfig / commit template / global
# ignore を /mnt/c 配下へ書き出す。
{
  config,
  pkgs,
  lib,
  ...
}:
let
  gitLib = import ../../../lib/settings/git.nix { inherit lib pkgs; };
  deploy = import ./deploy.nix { inherit lib; };

  windowsHomedir = config.my.windows.homedir;

  windowsCfg = gitLib.mkSettings {
    forWindows = true;
    windowsUsername = config.my.windows.username;
  };

  # Windows 用 .gitconfig は signing 由来のキーも明示的に含める
  # (programs.git.signing が自動付与してくれるキーを手動で再現)
  windowsGitIni = pkgs.writeText "windows-gitconfig" (
    lib.generators.toGitINI (
      windowsCfg
      // {
        user = windowsCfg.user // {
          signingkey = gitLib.signingKey;
        };
        commit = windowsCfg.commit // {
          gpgsign = true;
        };
        tag.gpgsign = true;
        gpg = windowsCfg.gpg // {
          format = "openpgp";
        };
      }
    )
  );

  windowsGitIgnore = pkgs.writeText "windows-gitignore-global" (
    lib.concatStringsSep "\n" gitLib.ignores
  );
in
{
  home.activation.deployWindowsGit = deploy.mkDeployActivation {
    dirs = [
      "${windowsHomedir}/.gitconfig.d"
      "${windowsHomedir}/.config/git"
    ];
    files = [
      {
        src = windowsGitIni;
        dst = "${windowsHomedir}/.gitconfig";
      }
      {
        src = gitLib.commitTemplate;
        dst = "${windowsHomedir}/.gitconfig.d/commit-template";
      }
      {
        src = windowsGitIgnore;
        dst = "${windowsHomedir}/.config/git/ignore";
      }
    ];
  };
}
