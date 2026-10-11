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
          attribution = {
            commit = "";
            pr = "";
          };
          autoMemoryEnabled = false;
          language = "japanese";
          model = config.dotfiles.agentModels.claude.main;
          # ユーザー設定のトップレベル effortLevel は旧形式で、Opus 5.5 以降には効かない。
          # CLAUDE_CODE_EFFORT_LEVEL は起動後のモデル/effort 切り替えより優先されるため使わない。
          # claude-code wrapper の --effort xhigh は、wrapper を通らない Windows や IDE からの起動には効かない。
          modelSettings.${config.dotfiles.agentModels.claude.main}.effortLevel = "xhigh";
          # 安全分類でフラグされた時に別モデルへ自動継続せず、確認で止める。
          switchModelsOnFlag = false;
          tui = "fullscreen";
          # 1M context は維持しつつ、Codex と近い 270k tokens 付近で自動圧縮する。
          # 圧縮閾値の割合に対応する設定キーはないため、CLAUDE_AUTOCOMPACT_PCT_OVERRIDE は env で渡す。
          autoCompactWindow = 300000;
          env = {
            USE_BUILTIN_RIPGREP = "0";
            CLAUDE_AUTOCOMPACT_PCT_OVERRIDE = "90";
            # macOS のトラックパッドだと速すぎるのでデフォルトの 3 のまま
            CLAUDE_CODE_SCROLL_SPEED = if config.dotfiles.platform.environment == "darwin" then "3" else "6";
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
