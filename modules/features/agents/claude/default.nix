{
  features,
  inputs,
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
    homeManager =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      import ./_lib/home.nix {
        inherit
          config
          inputs
          lib
          pkgs
          ;
      };
    windows =
      {
        config,
        lib,
        ...
      }:
      let
        pkgs = config._module.args.pkgs;
        settingsLib = import ./_lib/settings.nix { inherit lib; };
        settingsValidator = import ./_lib/settings-validator.nix { inherit pkgs; };
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
