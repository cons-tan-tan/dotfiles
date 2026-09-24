{ config, ... }:
let
  hm = config.flake.modules.homeManager;
in
{
  flake.modules.homeManager.agent-codex =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      codexHome = "${config.home.homeDirectory}/.codex";
      trashDirectory = "${config.xdg.dataHome}/Trash";
    in
    {
      key = "modules/features/agents/codex/default.nix#homeManager.agent-codex";
      imports = [
        hm.agents-base
        hm.agent-hcom-contract
        hm.agent-herdr
      ];
      options.dotfiles.codex.settings = lib.mkOption {
        type = (pkgs.formats.toml { }).type;
        default = { };
        description = "Managed Codex settings, merged with runtime-owned config fields.";
      };
      config = {
        dotfiles.unfreePackages = [ "codex-app" ];
        dotfiles.codex.settings = {
          personality = "pragmatic";
          model = config.dotfiles.agentModels.codex.model;
          model_reasoning_effort = config.dotfiles.agentModels.codex.reasoningEffort;

          approval_policy = "on-request";
          approvals_reviewer = "auto_review";

          # workspace のbaseline protectionsを維持したまま、開発用cacheと
          # recoverable deleteの保存先だけを追加で許可する。
          default_permissions = "local-dev";
          permissions = {
            local-dev = {
              description = "Workspace access with writable cache and trash.";
              extends = ":workspace";
              filesystem = {
                "~/.cache" = "write";
                "${trashDirectory}" = "write";
              };
            };
          };

          # Codex/Herdr hooks はこの module が導入するため feature gate も固定する。
          # Apps は GitHub connector の個別 disable が v0.139.0 では tool 注入へ
          # 効かないため、機能全体を落として GitHub app の露出を止める。
          # Remote plugin も個別 disable が v0.144.5 では skill 注入へ効かないため、
          # GitHub bundled skills を model context へ露出させないよう機能全体を落とす。
          features = {
            apps = false;
            hooks = true;
            remote_plugin = false;
          };

          plugins = {
            # GitHub 操作の権限境界は gh に一本化し、connector/MCP とそれらを
            # 優先する bundled skills は local/remote marketplace とも読み込まない。
            "github@openai-curated" = {
              enabled = false;
            };
            "github@openai-curated-remote" = {
              enabled = false;
            };
            "browser-use@openai-bundled" = {
              enabled = true;
            };
            "documents@openai-primary-runtime" = {
              enabled = true;
            };
            "spreadsheets@openai-primary-runtime" = {
              enabled = true;
            };
            "presentations@openai-primary-runtime" = {
              enabled = true;
            };
            "pdf@openai-primary-runtime" = {
              enabled = true;
            };
          };

          apps = {
            github = {
              enabled = false;
            };
          };

          skills = {
            config = [
              {
                path = "${codexHome}/skills/.system/skill-installer/SKILL.md";
                enabled = false;
              }
              {
                path = "${codexHome}/skills/herdr/SKILL.md";
                enabled = false;
              }
            ];
          };

          tui = {
            status_line = [
              "model-with-reasoning"
              "current-dir"
              "git-branch"
              "context-remaining"
              "five-hour-limit"
              "weekly-limit"
              "fast-mode"
            ];
          };
        };
      };
    };
}
