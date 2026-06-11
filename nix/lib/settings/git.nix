# git 設定の共有生成器。現ホスト用 (modules/home/programs/git.nix) と
# Windows companion 用 (modules/wsl/windows/git.nix) で共有する。
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
    # Editor
    ".vscode"
    ".idea"

    # direnv (.envrc は ignore しない: プロジェクトが意図的にコミットする
    # 場合があり、グローバル ignore だと差分が不可視になる)
    ".direnv"

    # Python
    ".venv"

    ## Ruff
    ".ruff.toml"

    # Docker
    "docker-compose.override.yml"

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

  # forWindows = true なら Windows companion 向け (パス・改行コードが Windows 前提)
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

      url."https://github.com/" = {
        insteadOf = [
          "git@github.com:"
          "ssh://git@github.com/"
        ];
      };
    };
}
