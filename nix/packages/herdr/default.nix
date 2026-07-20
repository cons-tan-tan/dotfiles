{
  lib,
  stdenvNoCC,
  fetchurl,
  fetchFromGitHub,
  writeText,
  runCommand,
  herdrPin ? builtins.fromJSON (builtins.readFile ../../pins/herdr.json),
}:
let
  system = stdenvNoCC.hostPlatform.system;
  inherit (herdrPin) version;
  asset = herdrPin.assets.${system} or (throw "herdr: unsupported system '${system}'");
  platforms = builtins.attrNames herdrPin.assets;
  src = fetchFromGitHub {
    owner = "ogulcancelik";
    repo = "herdr";
    rev = "v${version}";
    hash = herdrPin.srcHash;
  };
  # Use upstream release binaries on every supported platform so evaluation does
  # not need to import generated files from a fetched source derivation.
  herdrPackage = stdenvNoCC.mkDerivation {
    pname = "herdr";
    inherit version;

    src = fetchurl {
      url = "https://github.com/ogulcancelik/herdr/releases/download/v${version}/${asset.name}";
      inherit (asset) hash;
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
      inherit platforms;
      mainProgram = "herdr";
    };
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
  # Run Herdr's native installer in the sandbox and copy out the generated
  # artifact. extraInstall handles targets with an additional file.
  mkIntegration =
    {
      target,
      description,
      homeDir,
      outDir ? null,
      srcPath,
      destPath,
      mode,
      extraInstall ? "",
    }:
    runCommand "herdr-${target}-integration-${version}"
      {
        meta = {
          inherit description;
          homepage = "https://herdr.dev";
          license = lib.licenses.agpl3Plus;
          inherit platforms;
        };
      }
      ''
        home="$NIX_BUILD_TOP/home"
        mkdir -p "$home/${homeDir}" ${lib.optionalString (outDir != null) ''"$out/${outDir}"''}
        HOME="$home" XDG_CONFIG_HOME="$home/.config" ${herdrPackage}/bin/herdr integration install ${target} >/dev/null
        install -Dm${mode} "$home/${srcPath}" "$out/${destPath}"
        ${extraInstall}
      '';
in
rec {
  herdr = herdrPackage;

  herdr-agent-plugin =
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

  herdr-agent-skill =
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

  herdr-claude-integration = mkIntegration {
    target = "claude";
    description = "Herdr Claude Code native session restore integration hook";
    homeDir = ".claude";
    outDir = "hooks";
    srcPath = ".claude/hooks/herdr-agent-state.sh";
    destPath = "hooks/herdr-agent-state.sh";
    mode = "755";
    extraInstall = ''cp "$home/.claude/settings.json" "$out/settings.json"'';
  };

  herdr-codex-integration = mkIntegration {
    target = "codex";
    description = "Herdr Codex native session restore integration hook";
    homeDir = ".codex";
    srcPath = ".codex/herdr-agent-state.sh";
    destPath = "herdr-agent-state.sh";
    mode = "755";
  };

  herdr-pi-integration = mkIntegration {
    target = "pi";
    description = "Herdr Pi native agent state extension";
    homeDir = ".pi/agent/extensions";
    outDir = "extensions";
    srcPath = ".pi/agent/extensions/herdr-agent-state.ts";
    destPath = "extensions/herdr-agent-state.ts";
    mode = "644";
  };

  herdr-opencode-integration = mkIntegration {
    target = "opencode";
    description = "Herdr OpenCode native agent state plugin";
    homeDir = ".config/opencode";
    outDir = "plugins";
    srcPath = ".config/opencode/plugins/herdr-agent-state.js";
    destPath = "plugins/herdr-agent-state.js";
    mode = "644";
  };

  herdr-codex-marketplace =
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
        ln -s ${herdr-agent-plugin} "$out/plugins/herdr"
        cp ${codexMarketplaceJson} "$out/.agents/plugins/marketplace.json"
      '';
}
