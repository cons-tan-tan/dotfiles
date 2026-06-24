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
      # その他の feature flag は Codex 側の default / app state に任せる。
      features = {
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
