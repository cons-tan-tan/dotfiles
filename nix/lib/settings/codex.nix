# Codex config.toml の共有生成器。Codex 自身が動的に書く [projects]/[notice]
# などは既存 config から保持し、ここでは dotfiles 側で固定したい設定だけを
# merge payload として返す。
{ }:
let
  models = import ./models.nix;
in
{
  mkMergePayload =
    {
      codexHome,
    }:
    {
      __delete = [
        [
          "plugins"
          "herdr@herdr"
        ]
        [
          "marketplaces"
          "herdr"
        ]
        [
          "features"
          "network_proxy"
        ]
        [
          "permissions"
          "local-dev"
          "network"
        ]
      ];

      personality = "pragmatic";
      model = models.codex.model;
      model_reasoning_effort = models.codex.reasoningEffort;

      approval_policy = "on-request";
      approvals_reviewer = "auto_review";

      # 開発ツールは ~/.cache 配下へ書き込むものが多いため、workspace の
      # baseline protections を維持したまま共通キャッシュだけ追加で許可する。
      default_permissions = "local-dev";
      permissions = {
        local-dev = {
          description = "Workspace access with a writable user cache.";
          extends = ":workspace";
          filesystem = {
            "~/.cache" = "write";
          };
        };
      };

      # hcom hooks はこの module が導入するため feature gate も固定する。
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
}
