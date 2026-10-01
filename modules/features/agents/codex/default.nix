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
      # In v0.159.2, remote plugin state overrides local enabled settings.
      # Disable unwanted skills by qualified name until plugin-level disables work.
      # Names survive cache version changes without hiding same-named local skills.
      # Update this list for new or renamed skills. https://github.com/openai/codex/issues/28443
      # Default templates cannot be uninstalled either. https://github.com/openai/codex/issues/32513
      disabledSkillNames = [
        "openai-templates:artifact-template-analytics-dashboard"
        "openai-templates:artifact-template-business-review"
        "openai-templates:artifact-template-design-report"
        "openai-templates:artifact-template-experiment-analysis"
        "openai-templates:artifact-template-financial-budget"
        "openai-templates:artifact-template-investment-committee-memo"
        "openai-templates:artifact-template-legal-memorandum"
        "openai-templates:artifact-template-market-trends-report"
        "openai-templates:artifact-template-minimal-letterhead"
        "openai-templates:artifact-template-operating-calendar"
        "openai-templates:artifact-template-operating-review"
        "openai-templates:artifact-template-project-kickoff"
        "openai-templates:artifact-template-project-tracker"
        "openai-templates:artifact-template-sales-pipeline"
        "openai-templates:artifact-template-simple-dark-mode"
        "openai-templates:artifact-template-simple-light-mode"
        "openai-templates:artifact-template-strategy-memorandum"
        "openai-templates:artifact-template-system-design"
        "openai-templates:artifact-template-team-alignment"
        "openai-templates:artifact-template-three-statement-forecast"

        "pages:maintain-space"
        "pages:manage-schedules"
        "pages:organize-space"
        "pages:write-page"

        "work-pets:create-pet"
        "work-pets:pets"
        "work-pets:update-pet"

        "plugin-management:plugin-management"
      ];
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

          # This module installs Codex/Herdr hooks, so keep their feature gate on.
          # In v0.139.0, disabling the GitHub connector did not prevent tool injection;
          # disable Apps entirely to keep the GitHub app out of the tool inventory.
          # Disabling the remote catalog does not stop installed-plugin sync in
          # v0.159.2, so unwanted skills must also be disabled by name.
          features = {
            apps = false;
            hooks = true;
            remote_plugin = false;
          };

          plugins = {
            # Keep gh as the sole GitHub access boundary; request local and remote
            # disables for the connector/MCP and bundled skills that prefer them.
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
            ]
            ++ map (name: {
              inherit name;
              enabled = false;
            }) disabledSkillNames;
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
