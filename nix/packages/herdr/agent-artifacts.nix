{
  lib,
  writeText,
  runCommand,
  src,
  version,
  platforms,
}:
let
  pluginBase = {
    name = "herdr";
    inherit version;
    description = "Control herdr from inside herdr-managed panes.";
    author = {
      name = "Ogulcan Celik";
    };
    homepage = "https://herdr.dev";
    repository = "https://github.com/ogulcancelik/herdr";
    license = "AGPL-3.0-or-later";
    keywords = [
      "herdr"
      "terminal"
      "agents"
    ];
  };
  pluginInterface = {
    displayName = "Herdr";
    shortDescription = "Control herdr workspaces, tabs, panes, and agent state.";
    longDescription = "Adds the Herdr agent skill for controlling Herdr workspaces, tabs, panes, agent sessions, and local socket state from inside a Herdr-managed pane.";
    developerName = "Ogulcan Celik";
    category = "Productivity";
    capabilities = [
      "Terminal"
      "Agent orchestration"
    ];
    websiteURL = "https://herdr.dev";
  };
  claudePluginJson = writeText "herdr-claude-plugin.json" (builtins.toJSON pluginBase);
  codexPluginJson = writeText "herdr-codex-plugin.json" (
    builtins.toJSON (
      pluginBase
      // {
        skills = "./skills/";
        interface = pluginInterface;
      }
    )
  );
  codexMarketplaceJson = writeText "herdr-codex-marketplace.json" (
    builtins.toJSON {
      name = "herdr";
      interface = {
        displayName = "Herdr";
      };
      plugins = [
        {
          name = "herdr";
          source = {
            source = "local";
            path = "./plugins/herdr";
          };
          policy = {
            installation = "AVAILABLE";
            authentication = "ON_INSTALL";
          };
          category = "Productivity";
        }
      ];
    }
  );

  plugin =
    runCommand "herdr-agent-plugin-${version}"
      {
        meta = {
          description = "Herdr skill packaged as a Claude Code and Codex local plugin";
          homepage = "https://herdr.dev";
          license = lib.licenses.agpl3Plus;
          inherit platforms;
        };
      }
      ''
        mkdir -p "$out/.claude-plugin" "$out/.codex-plugin" "$out/skills/herdr"
        cp ${src}/SKILL.md "$out/skills/herdr/SKILL.md"
        cp ${claudePluginJson} "$out/.claude-plugin/plugin.json"
        cp ${codexPluginJson} "$out/.codex-plugin/plugin.json"
      '';
in
{
  inherit plugin;

  skill =
    runCommand "herdr-agent-skill-${version}"
      {
        meta = {
          description = "Herdr agent skill without plugin metadata";
          homepage = "https://herdr.dev";
          license = lib.licenses.agpl3Plus;
          inherit platforms;
        };
      }
      ''
        mkdir -p "$out"
        cp ${src}/SKILL.md "$out/SKILL.md"
      '';

  codexMarketplace =
    runCommand "herdr-codex-marketplace-${version}"
      {
        meta = {
          description = "Codex local marketplace exposing the Herdr plugin";
          homepage = "https://herdr.dev";
          license = lib.licenses.agpl3Plus;
          inherit platforms;
        };
      }
      ''
        mkdir -p "$out/.agents/plugins" "$out/plugins"
        ln -s ${plugin} "$out/plugins/herdr"
        cp ${codexMarketplaceJson} "$out/.agents/plugins/marketplace.json"
      '';
}
