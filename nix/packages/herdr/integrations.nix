{
  lib,
  runCommand,
  herdr,
  version,
  platforms,
}:
let
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
        HOME="$home" XDG_CONFIG_HOME="$home/.config" ${herdr}/bin/herdr integration install ${target} >/dev/null
        install -Dm${mode} "$home/${srcPath}" "$out/${destPath}"
        ${extraInstall}
      '';
in
{
  claude = mkIntegration {
    target = "claude";
    description = "Herdr Claude Code native session restore integration hook";
    homeDir = ".claude";
    outDir = "hooks";
    srcPath = ".claude/hooks/herdr-agent-state.sh";
    destPath = "hooks/herdr-agent-state.sh";
    mode = "755";
    extraInstall = ''cp "$home/.claude/settings.json" "$out/settings.json"'';
  };

  codex = mkIntegration {
    target = "codex";
    description = "Herdr Codex native session restore integration hook";
    homeDir = ".codex";
    srcPath = ".codex/herdr-agent-state.sh";
    destPath = "herdr-agent-state.sh";
    mode = "755";
  };

  pi = mkIntegration {
    target = "pi";
    description = "Herdr Pi native agent state extension";
    homeDir = ".pi/agent/extensions";
    outDir = "extensions";
    srcPath = ".pi/agent/extensions/herdr-agent-state.ts";
    destPath = "extensions/herdr-agent-state.ts";
    mode = "644";
  };

  opencode = mkIntegration {
    target = "opencode";
    description = "Herdr OpenCode native agent state plugin";
    homeDir = ".config/opencode";
    outDir = "plugins";
    srcPath = ".config/opencode/plugins/herdr-agent-state.js";
    destPath = "plugins/herdr-agent-state.js";
    mode = "644";
  };
}
