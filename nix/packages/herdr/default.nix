{
  lib,
  stdenvNoCC,
  fetchurl,
  fetchFromGitHub,
  writeText,
  runCommand,
  llm-agents,
}:
let
  system = stdenvNoCC.hostPlatform.system;
  versionData = builtins.fromJSON (builtins.readFile "${llm-agents}/packages/herdr/hashes.json");
  version = versionData.version;
  src = fetchFromGitHub {
    owner = "ogulcancelik";
    repo = "herdr";
    rev = "v${version}";
    hash = versionData.hash;
  };
  binaryAssets = {
    x86_64-linux = "herdr-linux-x86_64";
    aarch64-linux = "herdr-linux-aarch64";
    x86_64-darwin = "herdr-macos-x86_64";
    aarch64-darwin = "herdr-macos-aarch64";
  };
  binaryHashes = versionData.binaryHashes // {
    x86_64-linux = "sha256-4Vmg+svgoXzosEGXJNJLuEd9c0XKulFl91lBwSaotLk=";
    aarch64-linux = "sha256-pFpiZTM2PopGiR2Ab7wksJBKY9ZfheO0TJPMwBJBDSE=";
  };
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
in
rec {
  # llm-agents.nix builds Herdr from source on Linux and imports a generated Zig
  # file from that source path during package evaluation. This binary form keeps
  # our --no-build flake checks pure while tracking llm-agents' version.
  herdr = stdenvNoCC.mkDerivation {
    pname = "herdr";
    inherit version;

    src = fetchurl {
      url = "https://github.com/ogulcancelik/herdr/releases/download/v${version}/${binaryAssets.${system}}";
      hash = binaryHashes.${system};
    };

    dontUnpack = true;

    installPhase = ''
      runHook preInstall
      install -Dm755 "$src" "$out/bin/herdr"
      runHook postInstall
    '';

    meta = {
      description = "Terminal workspace manager for AI coding agents";
      homepage = "https://herdr.dev";
      changelog = "https://github.com/ogulcancelik/herdr/releases/tag/v${version}";
      license = lib.licenses.agpl3Plus;
      platforms = builtins.attrNames binaryAssets;
      mainProgram = "herdr";
    };
  };

  herdr-agent-plugin =
    runCommand "herdr-agent-plugin-${version}"
      {
        meta = {
          description = "Herdr skill packaged as a Claude Code and Codex local plugin";
          homepage = "https://herdr.dev";
          license = lib.licenses.agpl3Plus;
          platforms = builtins.attrNames binaryAssets;
        };
      }
      ''
        mkdir -p "$out/.claude-plugin" "$out/.codex-plugin" "$out/skills/herdr"
        cp ${src}/SKILL.md "$out/skills/herdr/SKILL.md"
        cp ${claudePluginJson} "$out/.claude-plugin/plugin.json"
        cp ${codexPluginJson} "$out/.codex-plugin/plugin.json"
      '';

  herdr-codex-marketplace =
    runCommand "herdr-codex-marketplace-${version}"
      {
        meta = {
          description = "Codex local marketplace exposing the Herdr plugin";
          homepage = "https://herdr.dev";
          license = lib.licenses.agpl3Plus;
          platforms = builtins.attrNames binaryAssets;
        };
      }
      ''
        mkdir -p "$out/.agents/plugins" "$out/plugins"
        ln -s ${herdr-agent-plugin} "$out/plugins/herdr"
        cp ${codexMarketplaceJson} "$out/.agents/plugins/marketplace.json"
      '';
}
