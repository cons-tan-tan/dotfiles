{ config, ... }:
let
  hm = config.flake.modules.homeManager;
in
{
  flake-file.inputs.codex-plugin-cc = {
    url = "github:openai/codex-plugin-cc";
    flake = false;
  };
  flake.modules.homeManager.agent-claude =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      key = "modules/features/agents/claude/default.nix#homeManager.agent-claude";
      imports = [
        hm.agents-base
        hm.agent-hcom-contract
        hm.agent-herdr
      ];
      options.dotfiles.claude.settings = lib.mkOption {
        type = (pkgs.formats.json { }).type;
        default = { };
        description = "Shared Claude settings before platform hooks and command policy are applied.";
      };
      config = {
        dotfiles.claude.settings = {
          includeCoAuthoredBy = false;
          autoMemoryEnabled = false;
          language = "japanese";
          model = config.dotfiles.agentModels.claude.main;
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
            ANTHROPIC_DEFAULT_SONNET_MODEL = config.dotfiles.agentModels.claude.sonnet;
            # CLAUDE_CODE_EFFORT_LEVEL はハードピンされ、起動後のモデル/effort
            # 切り替えより優先されるため使わない。起動時の xhigh 既定値は
            # claude-code wrapper の --effort xhigh で指定する。
            # macOS のトラックパッドだと速すぎるのでデフォルトの 3 のまま
            CLAUDE_CODE_SCROLL_SPEED = if config.dotfiles.platform.environment == "darwin" then "3" else "6";
            # サブエージェントも同じ Sonnet に固定する。
            CLAUDE_CODE_SUBAGENT_MODEL = config.dotfiles.agentModels.claude.sonnet;
          };
          permissions = {
            defaultMode = "auto";
            allow = [
              "WebSearch"
              "WebFetch(*)"
            ];
          };
        };
        dotfiles.cliTools = [
          {
            id = "claude-code";
            nix.route = "dotfiles-package";
            winget = {
              packageId = "Anthropic.ClaudeCode";
              description = "Claude Code CLI";
            };
          }
        ];
      };
    };
}
