{ ... }:
{
  features.windows-git = {
    name = "feature/windows/git";
    windows =
      {
        config,
        lib,
        ...
      }:
      let
        pkgs = config._module.args.pkgs;
        gitLib = import ../source-control/_lib/git.nix { inherit lib pkgs; };
        windowsCfg = gitLib.mkSettings {
          forWindows = true;
          windowsUsername = config.dotfiles.windows.username;
        };
        gitIni = pkgs.writeText "windows-gitconfig" (
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
        gitIgnore = pkgs.writeText "windows-gitignore-global" (lib.concatStringsSep "\n" gitLib.ignores);
      in
      {
        dotfiles.windows.deployments.git = {
          directories = [
            ".gitconfig.d"
            ".config/git"
          ];
          files = [
            {
              source = toString gitIni;
              destination = ".gitconfig";
            }
            {
              source = toString gitLib.commitTemplate;
              destination = ".gitconfig.d/commit-template";
            }
            {
              source = toString gitIgnore;
              destination = ".config/git/ignore";
            }
          ];
        };
      };
  };
}
