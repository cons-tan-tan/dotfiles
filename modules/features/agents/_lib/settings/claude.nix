# Claude Code settings.json の共有生成器。現ホスト用
# (modules/features/agents/_lib/home/claude.nix) と Windows companion 用
# (modules/wsl/windows/claude.nix) で共有する。
{
  lib,
  commandPolicy ? null,
}:
let
  models = import ./models.nix;
in
{
  # forWindows = true なら Windows companion 向け (hcom なし、Windows パス)。
  # hcomPath は POSIX ホストでフックが参照する hcom バイナリの絶対パス。
  # wslUserProfile は WSL 上の Claude Code だけに渡す Windows home の POSIX パス。
  mkSettings =
    {
      forWindows ? false,
      isDarwin ? false,
      wslUserProfile ? null,
      hcomPath ? null,
      guardCommand ? null,
    }:
    let
      commandPermissions =
        if forWindows then
          {
            allow = [ ];
            deny = [ ];
          }
        else if commandPolicy == null then
          throw "Claude settings require the merged agent command policy for non-Windows targets"
        else
          commandPolicy.mkClaudePermissions { };
    in
    {
      includeCoAuthoredBy = false;
      autoMemoryEnabled = false;
      language = "japanese";
      model = models.claude.main;
      effortLevel = "xhigh";
      # Fable 5 の安全分類でフラグされた時に Opus へ自動継続せず、確認で止める。
      switchModelsOnFlag = false;
      env = {
        USE_BUILTIN_RIPGREP = "0";
        CLAUDE_CODE_NO_FLICKER = "1";
        CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING = "1";
        # 1M context は維持しつつ、Codex と近い 270k tokens 付近で自動圧縮する。
        CLAUDE_CODE_AUTO_COMPACT_WINDOW = "300000";
        CLAUDE_AUTOCOMPACT_PCT_OVERRIDE = "90";
        # `sonnet` エイリアスを Sonnet 5.0 の固定 ID に向ける。
        # ANTHROPIC_DEFAULT_*_MODEL は完全なモデル名のみ許容するため、
        # Sonnet 更新時は models.nix の値だけを変更する。
        ANTHROPIC_DEFAULT_SONNET_MODEL = models.claude.sonnet;
        # CLAUDE_CODE_EFFORT_LEVEL はハードピンされ、起動後のモデル/effort
        # 切り替えより優先されるため使わない。起動時の xhigh 既定値は
        # claude-code wrapper の --effort xhigh で指定する。
        # macOS のトラックパッドだと速すぎるのでデフォルトの 3 のまま
        CLAUDE_CODE_SCROLL_SPEED = if isDarwin then "3" else "6";
        # サブエージェントも同じ Sonnet に固定する。
        CLAUDE_CODE_SUBAGENT_MODEL = models.claude.sonnet;
      }
      // lib.optionalAttrs (wslUserProfile != null) {
        # Claude Code 2.1.212 は WSL で未設定の USERPROFILE を PowerShell で
        # 取得する。起動時の取得が廃止されたらこの上書きを削除する。
        # https://github.com/anthropics/claude-code/issues/619#issuecomment-4106944524
        USERPROFILE = wslUserProfile;
      }
      // lib.optionalAttrs (!forWindows && hcomPath != null) {
        # フックが参照する hcom を store path に固定し PATH 非依存にする。
        HCOM = hcomPath;
      };
      permissions = {
        defaultMode = "auto";
        allow = [
          "WebSearch"
          "WebFetch(*)"
        ]
        ++ lib.optionals (!forWindows) commandPermissions.allow;
      }
      // lib.optionalAttrs (!forWindows) (
        {
          inherit (commandPermissions) deny;
        }
        // lib.optionalAttrs (commandPermissions ? ask) {
          inherit (commandPermissions) ask;
        }
      );
      # hcom 分の hooks/permissions はここに書かず、build 時に hcom の生成物と
      # マージする (claude.nix の mergedSettingsFile)。eval 時に生成 JSON を読む
      # (IFD) と、異種プラットフォーム向け構成の評価 (nix flake check 等) が
      # 壊れるため。
      hooks.PreToolUse = lib.optionals (!forWindows && guardCommand != null) [
        {
          matcher = "Bash";
          hooks = [
            {
              type = "command";
              command = guardCommand;
              timeout = 10;
            }
          ];
        }
      ];
      # programs.claude-code.settings 経由で HM が付与していた schema と揃える。
      "$schema" = "https://json.schemastore.org/claude-code-settings.json";
    };
}
