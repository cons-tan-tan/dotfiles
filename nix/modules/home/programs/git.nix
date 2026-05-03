{
  pkgs,
  lib,
  hostKind,
  windowsHomedir,
  ...
}:
let
  hk = import ../../../lib/host-kind.nix { inherit hostKind; };

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

  signingKey = "6250E02A31E09AFE";

  ignores = [
    # Editor
    ".vscode"
    ".idea"

    # direnv
    ".direnv"
    ".envrc"

    # Python
    ".venv"

    ## Ruff
    ".ruff.toml"

    # Mise
    "mise.local.toml"

    # Docker
    "docker-compose.override.yml"

    # Lefthook
    "*lefthook-local.*"

    # Claude Code
    "CLAUDE.local.md"
    "**/.claude/settings.local.json"

    # Backup files (commit skill)
    "*.local.bak"

    # macOS
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

  # hostKind ごとに変わる設定値だけを mkSettings の中に閉じ込める
  mkSettings =
    { hostKind }:
    let
      isWindows = hostKind == "windows";
    in
    {
      user = {
        name = "cons-tan-tan";
        email = "132136681+cons-tan-tan@users.noreply.github.com";
      };

      core = {
        editor = "code --wait";
        autocrlf = if isWindows then "true" else "input";
      };

      init.defaultBranch = "main";

      commit = {
        cleanup = "strip";
        template =
          if isWindows then
            "C:/Users/zhouc/.gitconfig.d/commit-template"
          else
            "${commitTemplate}";
      };

      gpg = lib.optionalAttrs isWindows {
        program = "C:/Program Files/GnuPG/bin/gpg.exe";
      };

      wt.basedir = ".worktrees";

      url."https://github.com/" = {
        insteadOf = [
          "git@github.com:"
          "ssh://git@github.com/"
        ];
      };
    };

  # 現ホスト用設定 (programs.git に渡す)
  cfg = mkSettings { inherit hostKind; };

  # Windows companion 用設定 (WSLホストで /mnt/c/... に配置)
  windowsCfg = mkSettings { hostKind = "windows"; };

  # Windows 用 .gitconfig は signing 由来のキーも明示的に含める
  # (programs.git.signing が自動付与してくれるキーを手動で再現)
  windowsGitIni = pkgs.writeText "windows-gitconfig" (
    lib.generators.toGitINI (
      windowsCfg
      // {
        user = windowsCfg.user // {
          signingkey = signingKey;
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

  windowsGitIgnore = pkgs.writeText "windows-gitignore-global" (lib.concatStringsSep "\n" ignores);
in
{
  programs.git = {
    enable = true;

    signing = {
      format = "openpgp";
      key = signingKey;
      signByDefault = true;
    };

    settings = cfg;

    inherit ignores;
  };

  home.activation = lib.mkIf hk.hasWindowsCompanion {
    deployWindowsGit = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run mkdir -p ${windowsHomedir}/.gitconfig.d ${windowsHomedir}/.config/git
      run install -m644 ${windowsGitIni} ${windowsHomedir}/.gitconfig
      run install -m644 ${commitTemplate} ${windowsHomedir}/.gitconfig.d/commit-template
      run install -m644 ${windowsGitIgnore} ${windowsHomedir}/.config/git/ignore
    '';
  };
}
