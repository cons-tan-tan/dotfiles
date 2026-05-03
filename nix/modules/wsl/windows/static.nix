{
  pkgs,
  lib,
  hostKind,
  dotfilesDir,
  windowsHomedir,
  ...
}:
let
  hk = import ../../../lib/host-kind.nix { inherit hostKind; };

  # Rules that only apply to the WSL/Linux Claude Code (depend on Linux-only tooling)
  windowsExcludedRules = [
    "nix.md"
    "nix.md.license"
    "web-fetch.md"
    "web-fetch.md.license"
  ];

  rsyncExcludeArgs = lib.concatMapStringsSep " " (f: "--exclude=${lib.escapeShellArg f}") windowsExcludedRules;
in
{
  home.activation = lib.mkIf hk.hasWindowsCompanion {
    deployWindowsClaudeStatic = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
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

      if [ -d "$HOME/.claude/skills" ]; then
        run ${pkgs.rsync}/bin/rsync -aL --delete \
          "$HOME/.claude/skills/" \
          "$WIN_CLAUDE/skills/"
      fi

      if [ -d "$HOME/.agents/skills" ]; then
        run ${pkgs.rsync}/bin/rsync -aL --delete \
          "$HOME/.agents/skills/" \
          "$WIN_AGENTS/skills/"
      fi
    '';
  };
}
