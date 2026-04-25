# Agent skills configuration for Claude Code
# https://github.com/Kyure-A/agent-skills-nix
#
# All skills (external and local) are managed here via agent-skills-nix.
# Skills are deployed to ~/.claude/skills and ~/.agents/skills
{
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
    };

    skills.explicit.pptx = {
      from = "anthropic";
      path = "pptx";
    };

    skills.explicit.drawio = {
      from = "drawio";
      path = "drawio";
    };

    # Deploy to skills directories (use built-in default paths)
    targets = {
      agents.enable = true;
      claude.enable = true;
    };
  };
}
