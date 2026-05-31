{
  config,
  pkgs,
  lib,
  hostKind,
  dotfilesDir,
  windowsHomedir,
  codex-plugin-cc,
  ...
}:
let
  hk = import ../../../lib/host-kind.nix { inherit hostKind; };

  # overlay (hcom-claude-hooks) が hcom 実行で生成したもの。手で写さず版に追従させる。
  hcomGenerated = builtins.fromJSON (builtins.readFile "${pkgs.hcom-claude-hooks}");

  mkSettings =
    { hostKind }:
    let
      isDarwin = hostKind == "darwin";
      isWindows = hostKind == "windows";

      hooksPath =
        if isWindows then "C:/Users/zhouc/.claude/hooks/validate-gh-api.sh" else "~/.claude/hooks/validate-gh-api.sh";
    in
    {
      includeCoAuthoredBy = false;
      autoMemoryEnabled = false;
      language = "japanese";
      model = "opus[1m]";
      env = {
        USE_BUILTIN_RIPGREP = "0";
        CLAUDE_CODE_NO_FLICKER = "1";
        CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING = "1";
        # コーディング用途は xhigh 推奨 (Opus 4.8 公式ガイド)。
        # settings.json の effortLevel では xhigh 固定にできない (実測で確認済み):
        #   - Opus 4.8 初回起動時にモデル既定値 (high) へリセットされる仕様
        #   - さらに毎セッション再発火するバグ anthropics/claude-code#62783 (未解決)
        # env 変数はハードピン (最優先・上書き不可) なので両方を回避できる。
        # 修正されたら settings.json 側へ戻すか要検討。
        CLAUDE_CODE_EFFORT_LEVEL = "xhigh";
        # macOS のトラックパッドだと速すぎるのでデフォルトの 3 のまま
        CLAUDE_CODE_SCROLL_SPEED = if isDarwin then "3" else "6";
        # サブエージェントを最新 Sonnet に固定する。
        # この変数はエイリアス (sonnet) を受け付けず完全なモデル名のみ許容するため、
        # Sonnet 更新時はここを書き換える必要がある。
        CLAUDE_CODE_SUBAGENT_MODEL = "claude-sonnet-4-6";
      }
      // lib.optionalAttrs (!isWindows) {
        # フックが参照する hcom を store path に固定し PATH 非依存にする。
        HCOM = "${pkgs.hcom}/bin/hcom";
      };
      permissions = {
        allow = [
          "WebSearch"
          "WebFetch(*)"
          "Bash(rg *)"
          "Bash(bat *)"
          "Bash(eza *)"
          "Bash(jq *)"
          "Bash(fd *)"
          "Bash(ast-grep *)"
          "Bash(gh issue list *)"
          "Bash(gh issue view *)"
          "Bash(gh pr list *)"
          "Bash(gh pr view *)"
          "Bash(gh pr diff *)"
          "Bash(gh pr checks *)"
          "Bash(gh run list *)"
          "Bash(gh run view *)"
          "Bash(gh repo view *)"
          "Bash(gh search *)"
          "Bash(gh api-get *)"
          "Bash(curl-fetch *)"
        ]
        # hcom 分は生成物から取る (手書きで二重管理しない)。
        ++ lib.optionals (!isWindows) hcomGenerated.permissions.allow
        ++ lib.optionals isWindows [
          "Bash(wsl.exe *)"
          "Bash(pwsh.exe *)"
        ];
        deny = [
          "Bash(rm -rf *)"
          "Bash(fd *--exec*)"
          "Bash(fd *--exec-batch*)"
          "Bash(fd *-x *)"
          "Bash(fd *-X *)"
        ]
        ++ lib.optionals isWindows [
          "Bash(Remove-Item -Recurse -Force *)"
        ];
      };
      hooks =
        let
          ghApiHook = {
            matcher = "Bash";
            hooks = [
              {
                type = "command";
                command = hooksPath;
              }
            ];
          };
        in
        # Windows companion には hcom (linux/darwin バイナリ) が無いので gh-api guard だけ。
        if isWindows then
          { PreToolUse = [ ghApiHook ]; }
        else
          hcomGenerated.hooks
          // {
            # hcom も PreToolUse を使うため、gh-api guard と両立させる。
            PreToolUse = hcomGenerated.hooks.PreToolUse ++ [ ghApiHook ];
          };
    };

  windowsSettings = mkSettings { hostKind = "windows"; };
  windowsSettingsFile =
    (pkgs.formats.json { }).generate "claude-windows-settings.json" windowsSettings;
in
{
  programs.claude-code = {
    enable = true;
    plugins = [
      "${codex-plugin-cc}/plugins/codex"
    ];
    settings = mkSettings { inherit hostKind; };
  };

  home.file.".claude/CLAUDE.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/claude/CLAUDE.md";
  home.file.".claude/commands".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/claude/commands";
  home.file.".claude/rules".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/claude/rules";
  home.file.".claude/output-styles".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/claude/output-styles";
  home.file.".claude/hooks".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/claude/hooks";

  home.activation = lib.mkIf hk.hasWindowsCompanion {
    deployWindowsClaudeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run mkdir -p ${windowsHomedir}/.claude
      run install -m644 ${windowsSettingsFile} ${windowsHomedir}/.claude/settings.json
    '';
  };
}
