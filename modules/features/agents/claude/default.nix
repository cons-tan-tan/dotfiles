{
  features,
  ...
}:
let
  payload = import ./_interface/payload.nix;
in
{
  flake-file.inputs.codex-plugin-cc = {
    url = "github:openai/codex-plugin-cc";
    flake = false;
  };

  features.agent-claude = {
    name = "feature/agents/claude";
    includes = [
      features.agents-base
      features.agent-hcom-contract
      features.agent-herdr
    ];
    cli-tools = [
      {
        id = "claude-code";
        nix.route = "dotfiles-package";
        winget = {
          packageId = "Anthropic.ClaudeCode";
          description = "Claude Code CLI";
        };
      }
    ];
    windows =
      {
        config,
        lib,
        ...
      }:
      let
        pkgs = config._module.args.pkgs;
        settingsLib = import ./_interface/settings.nix { inherit lib; };
        settingsValidator = import ./_interface/settings-validator.nix {
          inherit pkgs;
          schemaPin = import ./_interface/settings-schema.nix;
        };
        raw = (pkgs.formats.json { }).generate "claude-windows-settings.json" (
          settingsLib.mkSettings { forWindows = true; }
        );
        source = settingsValidator.validate "claude-windows-settings.json" raw;
      in
      {
        dotfiles.windows = {
          deployments.claude = {
            directories = [ ".claude" ];
            files = [
              {
                source = toString source;
                destination = ".claude/settings.json";
              }
            ];
          };
          staticResources.claude.trees = [
            {
              source = "${config.dotfiles.platform.source}/${payload.repositoryRelative.commands}";
              destination = ".claude/commands";
            }
            {
              source = "${config.dotfiles.platform.source}/${payload.repositoryRelative.outputStyles}";
              destination = ".claude/output-styles";
            }
            {
              source = "${config.dotfiles.platform.source}/${payload.repositoryRelative.hooks}";
              destination = ".claude/hooks";
            }
          ];
        };
      };
  };
}
