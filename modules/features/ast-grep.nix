{
  inputs,
  ...
}:
{
  flake-file.inputs.ast-grep-skill = {
    url = "github:ast-grep/claude-skill";
    flake = false;
  };

  flake.modules.homeManager.ast-grep = {
    key = "modules/features/ast-grep.nix#homeManager.ast-grep";
    dotfiles.cliTools = [
      {
        id = "ast-grep";
        nix = {
          route = "home-packages";
          nixpkgsAttr = "ast-grep";
        };
        winget = {
          packageId = "ast-grep.ast-grep";
          description = "ast-grep";
        };
      }
    ];
    dotfiles.agentSkillContributions = [
      {
        name = "ast-grep";
        provenance = "external";
        definition = {
          root = inputs.ast-grep-skill.outPath + "/ast-grep/skills/ast-grep";
          customization.frontmatter.description = "Performs syntax-aware structural code search when tasks require matching language constructs, nested relationships, or code patterns that plain-text search cannot express reliably.";
        };
      }
    ];
    dotfiles.agentCommandPolicyContributions = [
      {
        owner = "feature/ast-grep";
        policy.commands.ast-grep = true;
      }
    ];
  };
}
