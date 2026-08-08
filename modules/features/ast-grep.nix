{
  inputs,
  ...
}:
{
  flake-file.inputs.ast-grep-skill = {
    url = "github:ast-grep/claude-skill";
    flake = false;
  };

  features.ast-grep =
    { config, ... }:
    {
      name = "feature/ast-grep";
      cli-tools = [
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
      agent-skills = [
        {
          name = "ast-grep";
          provenance = "external";
          definition = {
            root = inputs.ast-grep-skill.outPath + "/ast-grep/skills/ast-grep";
            customization.frontmatter.description = "Performs syntax-aware structural code search when tasks require matching language constructs, nested relationships, or code patterns that plain-text search cannot express reliably.";
          };
        }
      ];
      agent-command-policy = [
        {
          owner = config.name;
          policy.commands.ast-grep = true;
        }
      ];
    };
}
