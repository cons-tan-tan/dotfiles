{
  config,
  pkgs,
  lib,
  hostKind,
  dotfilesDir,
  windowsHomedir,
  codex-plugin-cc,
  ...
}:
let
  hk = import ../../../lib/host-kind.nix { inherit hostKind; };

  mkSettings =
    { hostKind }:
    let
      isDarwin = hostKind == "darwin";
      isWindows = hostKind == "windows";

      hooksPath =
        if isWindows then "C:/Users/zhouc/.claude/hooks/validate-gh-api.sh" else "~/.claude/hooks/validate-gh-api.sh";
    in
    {
      includeCoAuthoredBy = false;
      language = "japanese";
      model = "opus[1m]";
      effortLevel = "high";
      env = {
        USE_BUILTIN_RIPGREP = "0";
        CLAUDE_CODE_NO_FLICKER = "1";
        CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING = "1";
        # macOS のトラックパッドだと速すぎるのでデフォルトの 3 のまま
        CLAUDE_CODE_SCROLL_SPEED = if isDarwin then "3" else "6";
      };
      permissions = {
        allow = [
          "WebSearch"
          "WebFetch(*)"
          "Bash(rg *)"
          "Bash(bat *)"
          "Bash(eza *)"
          "Bash(jq *)"
          "Bash(fd *)"
          "Bash(ast-grep *)"
          "Bash(gh issue list *)"
          "Bash(gh issue view *)"
          "Bash(gh pr list *)"
          "Bash(gh pr view *)"
          "Bash(gh pr diff *)"
          "Bash(gh pr checks *)"
          "Bash(gh run list *)"
          "Bash(gh run view *)"
          "Bash(gh search *)"
          "Bash(gh api-get *)"
          "Bash(curl-fetch *)"
        ]
        ++ lib.optionals isWindows [
          "Bash(wsl.exe *)"
          "Bash(pwsh.exe *)"
        ];
        deny = [
          "Bash(rm -rf *)"
          "Bash(fd *--exec*)"
          "Bash(fd *--exec-batch*)"
          "Bash(fd *-x *)"
          "Bash(fd *-X *)"
        ]
        ++ lib.optionals isWindows [
          "Bash(Remove-Item -Recurse -Force *)"
        ];
      };
      hooks = {
        PreToolUse = [
          {
            matcher = "Bash";
            hooks = [
              {
                type = "command";
                command = hooksPath;
              }
            ];
          }
        ];
      };
    };

  windowsSettings = mkSettings { hostKind = "windows"; };
  windowsSettingsFile =
    (pkgs.formats.json { }).generate "claude-windows-settings.json" windowsSettings;
in
{
  programs.claude-code = {
    enable = true;
    plugins = [
      "${codex-plugin-cc}/plugins/codex"
    ];
    settings = mkSettings { inherit hostKind; };
  };

  home.file.".claude/CLAUDE.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/claude/CLAUDE.md";
  home.file.".claude/commands".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/claude/commands";
  home.file.".claude/rules".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/claude/rules";
  home.file.".claude/output-styles".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/claude/output-styles";
  home.file.".claude/hooks".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/claude/hooks";

  home.activation = lib.mkIf hk.hasWindowsCompanion {
    deployWindowsClaudeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run mkdir -p ${windowsHomedir}/.claude
      run install -m644 ${windowsSettingsFile} ${windowsHomedir}/.claude/settings.json
    '';
  };
}
