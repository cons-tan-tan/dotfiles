# Codex config.toml の共有生成器。Codex 自身が動的に書く [projects]/[notice]
# などは既存 config から保持し、ここでは dotfiles 側で固定したい設定だけを
# merge payload として返す。
{ }:
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
      ];

      personality = "pragmatic";
      model = "gpt-5.5";
      model_reasoning_effort = "xhigh";

      approval_policy = "on-request";
      approvals_reviewer = "auto_review";

      # hcom hooks はこの module が導入するため feature gate も固定する。
      # Apps は GitHub connector の個別 disable が v0.139.0 では tool 注入へ
      # 効かないため、機能全体を落として GitHub app の露出を止める。
      features = {
        apps = false;
        hooks = true;
      };

      plugins = {
        "github@openai-curated" = {
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
