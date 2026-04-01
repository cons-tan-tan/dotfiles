# Agent skills configuration for Claude Code
# https://github.com/Kyure-A/agent-skills-nix
#
# All skills (external and local) are managed here via agent-skills-nix.
# Skills are deployed to ~/.claude/skills and ~/.agents/skills
{
  ast-grep-skill,
  agent-browser-skill,
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

    # Deploy to skills directories (use built-in default paths)
    targets = {
      agents.enable = true;
      claude.enable = true;
    };
  };
}
