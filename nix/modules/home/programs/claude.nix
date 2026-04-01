{ config, dotfilesDir, codex-plugin-cc, ... }:
{
  programs.claude-code = {
    enable = true;
    plugins = [
      "${codex-plugin-cc}/plugins/codex"
    ];
    settings = {
      includeCoAuthoredBy = false;
      language = "japanese";
      model = "opus[1m]";
      env = {
        USE_BUILTIN_RIPGREP = "0";
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
          "Bash(gh api-get *)"
        ];
        deny = [
          "Bash(rm -rf *)"
          "Bash(fd *--exec*)"
          "Bash(fd *--exec-batch*)"
          "Bash(fd *-x *)"
          "Bash(fd *-X *)"
        ];
      };
      hooks = {
        PreToolUse = [
          {
            matcher = "Bash";
            hooks = [
              {
                type = "command";
                command = "~/.claude/hooks/validate-gh-api.sh";
              }
            ];
          }
        ];
      };
    };
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
}
