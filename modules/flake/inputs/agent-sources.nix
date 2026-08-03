{
  flake-file.inputs = {
    anthropic-skills = {
      url = "github:anthropics/skills";
      flake = false;
    };
    ast-grep-skill = {
      url = "github:ast-grep/claude-skill";
      flake = false;
    };
    codex-plugin-cc = {
      url = "github:openai/codex-plugin-cc";
      flake = false;
    };
    drawio-skill = {
      url = "github:jgraph/drawio-mcp";
      flake = false;
    };
    improve-skill = {
      url = "github:shadcn/improve";
      flake = false;
    };
  };
}
