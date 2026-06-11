{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (config.my) dotfilesDir;
  windowsHomedir = config.my.windows.homedir;

  # Rules that only apply to the WSL/Linux Claude Code (depend on Linux-only tooling)
  windowsExcludedRules = [
    "nix.md"
    "nix.md.license"
    "web-fetch.md"
    "web-fetch.md.license"
  ];

  rsyncExcludeArgs = lib.concatMapStringsSep " " (
    f: "--exclude=${lib.escapeShellArg f}"
  ) windowsExcludedRules;
in
{
  # linkGeneration の後に実行する: ~/.claude/skills と ~/.agents/skills は
  # home.file (agent-skills モジュール) が同じ activation 内で張る symlink
  # なので、writeBoundary 基準だと初回 switch でまだ存在せず skills が
  # Windows 側へ配られない。
  home.activation.deployWindowsClaudeStatic = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    WIN_CLAUDE=${windowsHomedir}/.claude
    WIN_AGENTS=${windowsHomedir}/.agents

    run mkdir -p "$WIN_CLAUDE" "$WIN_AGENTS/skills"

    run ${pkgs.rsync}/bin/rsync -aL --delete \
      ${dotfilesDir}/claude/CLAUDE.md \
      "$WIN_CLAUDE/CLAUDE.md"

    run ${pkgs.rsync}/bin/rsync -aL --delete ${rsyncExcludeArgs} \
      ${dotfilesDir}/claude/rules/ \
      "$WIN_CLAUDE/rules/"

    for dir in commands output-styles hooks; do
      run ${pkgs.rsync}/bin/rsync -aL --delete \
        ${dotfilesDir}/claude/$dir/ \
        "$WIN_CLAUDE/$dir/"
    done

    run ${pkgs.rsync}/bin/rsync -aL --delete \
      "$HOME/.claude/skills/" \
      "$WIN_CLAUDE/skills/"

    run ${pkgs.rsync}/bin/rsync -aL --delete \
      "$HOME/.agents/skills/" \
      "$WIN_AGENTS/skills/"
  '';
}
