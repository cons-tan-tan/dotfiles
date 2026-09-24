let
  gitSettings =
    { lib, pkgs }:
    rec {
      signingKey = "6250E02A31E09AFE";

      commitTemplate = pkgs.writeText "git-commit-template" ''

        # prefix(optional scope): description

        # ==== prefix ====
        # feat: 新しい機能
        # fix: バグの修正
        # docs: ドキュメントのみの変更
        # style: フォーマットの変更
        # refactor: リファクタリングのための変更
        # perf: パフォーマンスの改善のための変更
        # test: テスト関連
        # build: ビルドシステムや外部依存に関する変更
        # ci: CI用の設定やスクリプトに関する変更
        # chore: その他の変更
        # revert: 以前のコミットに復帰
      '';

      ignores = [
        ".vscode"
        ".idea"
        ".direnv"
        ".nix-local/"
        ".venv"
        ".ruff.toml"
        "docker-compose.override.yml"
        "CLAUDE.local.md"
        "**/.claude/settings.local.json"
        "**/.claude/worktrees/"
        "*.local.bak"
        ".DS_Store"
        "__MACOSX/"
        ".AppleDouble"
        ".LSOverride"
        "Icon\r"
        "._*"
        ".DocumentRevisions-V100"
        ".fseventsd"
        ".Spotlight-V100"
        ".TemporaryItems"
        ".Trashes"
        ".VolumeIcon.icns"
        ".com.apple.timemachine.donotpresent"
        ".AppleDB"
        ".AppleDesktop"
        "Network Trash Folder"
        "Temporary Items"
        ".apdisk"
      ];

      mkSettings =
        {
          forWindows ? false,
          windowsUsername ? null,
        }:
        {
          user = {
            name = "cons-tan-tan";
            email = "132136681+cons-tan-tan@users.noreply.github.com";
          };
          core = {
            editor = "code --wait";
            autocrlf = if forWindows then "true" else "input";
          };
          init.defaultBranch = "main";
          commit = {
            cleanup = "strip";
            template =
              if forWindows then
                "C:/Users/${windowsUsername}/.gitconfig.d/commit-template"
              else
                "${commitTemplate}";
          };
          gpg = lib.optionalAttrs forWindows {
            program = "C:/Program Files/GnuPG/bin/gpg.exe";
          };
          wt.basedir = ".worktrees";
          url."https://github.com/".insteadOf = [
            "git@github.com:"
            "ssh://git@github.com/"
          ];
        };
    };
in
{
  flake.modules.homeManager.git = {
    key = "modules/features/git/default.nix#homeManager.git";
    imports = [
      (
        { lib, pkgs, ... }:
        let
          gitLib = gitSettings { inherit lib pkgs; };
        in
        {
          home.packages = [ pkgs.git-cliff ];

          programs.git = {
            enable = true;
            settings = gitLib.mkSettings { };
            inherit (gitLib) ignores;
          };
        }
      )

      ({ config, lib, ... }: {
        config = lib.mkIf config.dotfiles.platform.windows.enable (
          let
            pkgs = config._module.args.pkgs;
            gitLib = gitSettings { inherit lib pkgs; };
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
          }
        );
      })

    ];
    dotfiles.cliTools = [
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
    dotfiles.agentCommandPolicyContributions = [
      {
        owner = "feature/git";
        policy.commands.git = {
          clone = true;
          commit = true;
        };
      }
    ];
  };

  flake.modules.homeManager.git-signing-openpgp =
    { lib, pkgs, ... }:
    {
      key = "modules/features/git/default.nix#homeManager.git-signing-openpgp";

      programs.git.signing = {
        format = "openpgp";
        key = (gitSettings { inherit lib pkgs; }).signingKey;
        signByDefault = true;
      };
    };
}
