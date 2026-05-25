# Agent skills configuration for Claude Code
# https://github.com/Kyure-A/agent-skills-nix
#
# All skills (external and local) are managed here via agent-skills-nix.
# Skills are deployed to ~/.claude/skills and ~/.agents/skills
{
  lib,
  ast-grep-skill,
  agent-browser-skill,
  agent-slack-skill,
  anthropic-skills,
  drawio-skill,
  ...
}:
{
  programs.agent-skills = {
    enable = true;

    # Skill sources (from flake inputs)
    sources = {
      # External: ast-grep official skill
      ast-grep = {
        path = ast-grep-skill;
        subdir = "ast-grep/skills";
      };
      # External: agent-browser skill
      agent-browser = {
        path = agent-browser-skill;
        subdir = "skills";
      };
      # External: agent-slack skill
      agent-slack = {
        path = agent-slack-skill;
        subdir = "skills";
      };
      # External: Anthropic official skills
      anthropic = {
        path = anthropic-skills;
        subdir = "skills";
      };
      # External: draw.io skill
      drawio = {
        path = drawio-skill;
        subdir = "skill-cli";
      };
      # Local: skills from this dotfiles repo
      local = {
        path = ../../..;
        subdir = "agents/skills";
      };
    };

    # Enable all local skills
    skills.enableAll = [ "local" ];

    skills.explicit.ast-grep = {
      from = "ast-grep";
      path = "ast-grep";
    };

    skills.explicit.agent-browser = {
      from = "agent-browser";
      path = "agent-browser";
    };

    skills.explicit.agent-slack = {
      from = "agent-slack";
      path = "agent-slack";
      transform =
        { original, ... }:
        let
          parts = lib.splitString "\n---\n" original;
          hasFm = builtins.length parts > 1 && lib.hasPrefix "---\n" original;
          body = if hasFm then lib.concatStringsSep "\n---\n" (builtins.tail parts) else original;
          # Keep skill descriptions compact because some metadata consumers impose
          # length limits; avoid a separate trigger-word list unless it adds signal.
          frontmatter = ''
            ---
            name: agent-slack
            description: |
              Slack automation CLI for AI agents. Use when the user asks to read,
              search, send, reply to, edit, delete, or react to Slack messages;
              inspect threads, channels, DMs, unread messages, saved-for-later items,
              files, canvases, users, or workflows; upload local files to Slack; or
              manage channels and conversations.
            ---
          '';
        in
        frontmatter + body;
    };

    skills.explicit.pptx = {
      from = "anthropic";
      path = "pptx";
    };

    skills.explicit.drawio = {
      from = "drawio";
      path = "drawio";
      transform =
        { original, ... }:
        let
          parts = lib.splitString "\n---\n" original;
          hasFm = builtins.length parts > 1 && lib.hasPrefix "---\n" original;
          frontmatter = if hasFm then builtins.head parts + "\n---\n" else "";
          body = if hasFm then lib.concatStringsSep "\n---\n" (builtins.tail parts) else original;
          override = ''

            > **Local override (WSL2)**: use `drawio` from `$PATH` for exports —
            > it is a Linux headless wrapper that already injects `--no-sandbox`,
            > `--disable-gpu`, and starts Xvfb / D-Bus. Do not add these flags or
            > call `/mnt/c/.../draw.io.exe` for the export step; the "Opening the
            > result" instructions below still apply.
          '';
        in
        frontmatter + override + body;
    };

    # Deploy to skills directories (use built-in default paths)
    targets = {
      agents.enable = true;
      claude.enable = true;
    };
  };
}
