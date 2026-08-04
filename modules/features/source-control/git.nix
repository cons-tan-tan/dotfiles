{ ... }:
{
  features.source-control-git = {
    name = "feature/source-control/git";
    cli-tools = [
      {
        id = "git";
        nix.route = "programs";
        winget = {
          packageId = "Git.Git";
          elevated = true;
          description = "Git for Windows";
        };
      }
    ];
    homeManager =
      { lib, pkgs, ... }:
      let
        gitLib = import ./_lib/git.nix { inherit lib pkgs; };
      in
      {
        programs.git = {
          enable = true;
          signing = {
            format = "openpgp";
            key = gitLib.signingKey;
            signByDefault = true;
          };
          settings = gitLib.mkSettings { };
          inherit (gitLib) ignores;
        };
      };
    windows =
      {
        config,
        lib,
        ...
      }:
      let
        pkgs = config._module.args.pkgs;
        gitLib = import ./_lib/git.nix { inherit lib pkgs; };
        windowsCfg = gitLib.mkSettings {
          forWindows = true;
          windowsUsername = config.dotfiles.platform.windows.username;
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
