# Claude Code settings.json の共有生成器。現ホスト用
# (modules/home/programs/claude.nix) と Windows companion 用
# (modules/wsl/windows/claude.nix) で共有する。
{ lib }:
{
  # forWindows = true なら Windows companion 向け (hcom なし、Windows パス)。
  # hcomPath は POSIX ホストでフックが参照する hcom バイナリの絶対パス。
  mkSettings =
    {
      forWindows ? false,
      isDarwin ? false,
      windowsUsername ? null,
      hcomPath ? null,
    }:
    {
      includeCoAuthoredBy = false;
      autoMemoryEnabled = false;
      language = "japanese";
      model = "claude-opus-4-7[1m]";
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
        # Sonnet 更新時はここを書き換える必要がある。
        ANTHROPIC_DEFAULT_SONNET_MODEL = "claude-sonnet-5";
        # CLAUDE_CODE_EFFORT_LEVEL はハードピンされ、起動後のモデル/effort
        # 切り替えより優先されるため使わない。起動時の xhigh 既定値は
        # claude-code wrapper の --effort xhigh で指定する。
        # macOS のトラックパッドだと速すぎるのでデフォルトの 3 のまま
        CLAUDE_CODE_SCROLL_SPEED = if isDarwin then "3" else "6";
        # サブエージェントも同じ Sonnet に固定する。
        CLAUDE_CODE_SUBAGENT_MODEL = "claude-sonnet-5";
      }
      // lib.optionalAttrs (!forWindows) {
        # フックが参照する hcom を store path に固定し PATH 非依存にする。
        HCOM = hcomPath;
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
        ++ lib.optionals forWindows [
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
        ++ lib.optionals forWindows [
          "Bash(Remove-Item -Recurse -Force *)"
        ];
      };
      # hcom 分の hooks/permissions はここに書かず、build 時に hcom の生成物と
      # マージする (claude.nix の mergedSettingsFile)。eval 時に生成 JSON を読む
      # (IFD) と、異種プラットフォーム向け構成の評価 (nix flake check 等) が
      # 壊れるため。
      hooks.PreToolUse = [ ];
      # programs.claude-code.settings 経由で HM が付与していた schema と揃える。
      "$schema" = "https://json.schemastore.org/claude-code-settings.json";
    };
}
