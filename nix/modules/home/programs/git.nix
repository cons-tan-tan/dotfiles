{ pkgs, ... }:
let
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
in
{
  programs.git = {
    enable = true;

    signing = {
      key = "6250E02A31E09AFE";
      signByDefault = true;
    };

    settings = {
      user = {
        name = "cons-tan-tan";
        email = "132136681+cons-tan-tan@users.noreply.github.com";
      };

      core = {
        editor = "code --wait";
        autocrlf = "input";
      };

      init.defaultBranch = "main";

      commit = {
        cleanup = "strip";
        template = "${commitTemplate}";
      };

      wt.basedir = ".worktrees";

      url = {
        "https://github.com/" = {
          insteadOf = [
            "git@github.com:"
            "ssh://git@github.com/"
          ];
        };
      };
    };

    ignores = [
      # Editor
      ".vscode"
      ".idea"

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

      # Patch files (git-commit-crafter)
      ".patch"

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
  };
}
