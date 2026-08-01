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
    "tools.md"
    "tools.md.license"
    "web-fetch.md"
    "web-fetch.md.license"
  ];

  # ax CLI はNix側だけに導入するため、command not foundになるSkillを
  # Windows companionへ配らない。
  windowsExcludedSkills = [ "ax/" ];

  mkRsyncExcludeArgs =
    values: lib.concatMapStringsSep " " (f: "--exclude=${lib.escapeShellArg f}") values;
  ruleRsyncExcludeArgs = mkRsyncExcludeArgs windowsExcludedRules;
  skillRsyncExcludeArgs = mkRsyncExcludeArgs windowsExcludedSkills;
in
{
  # linkGeneration の後に実行する: ~/.claude/skills と ~/.agents/skills は
  # home.file (agent-skills モジュール) が同じ activation 内で張る symlink
  # なので、writeBoundary 基準だと初回 switch でまだ存在せず skills が
  # Windows 側へ配られない。
  home.activation.deployWindowsClaudeStatic = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    WIN_CLAUDE="${windowsHomedir}/.claude"
    WIN_AGENTS="${windowsHomedir}/.agents"

    run mkdir -p "$WIN_CLAUDE" "$WIN_AGENTS/skills"

    run ${pkgs.rsync}/bin/rsync -aL --delete \
      "${dotfilesDir}/agents/context/global.md" \
      "$WIN_CLAUDE/CLAUDE.md"

    run ${pkgs.rsync}/bin/rsync -aL --delete --delete-excluded ${ruleRsyncExcludeArgs} \
      "${dotfilesDir}/agents/context/rules/" \
      "$WIN_CLAUDE/rules/"

    for dir in commands output-styles hooks; do
      run ${pkgs.rsync}/bin/rsync -aL --delete \
        "${dotfilesDir}/claude/$dir/" \
        "$WIN_CLAUDE/$dir/"
    done

    run ${pkgs.rsync}/bin/rsync -aL --delete --delete-excluded ${skillRsyncExcludeArgs} \
      "$HOME/.claude/skills/" \
      "$WIN_CLAUDE/skills/"

    run ${pkgs.rsync}/bin/rsync -aL --delete --delete-excluded ${skillRsyncExcludeArgs} \
      "$HOME/.agents/skills/" \
      "$WIN_AGENTS/skills/"
  '';
}
