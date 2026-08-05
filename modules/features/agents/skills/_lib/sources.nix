# デプロイ対象 skill の宣言。root は SKILL.md を含むディレクトリ。
# customization (任意) で frontmatter / body / invocation policy を変更する。
{ inputs }:
let
  inherit (inputs)
    ast-grep-skill
    anthropic-skills
    drawio-skill
    improve-skill
    ;
in
{
  ast-grep = {
    root = ast-grep-skill.outPath + "/ast-grep/skills/ast-grep";
    customization.frontmatter.description = "Performs syntax-aware structural code search when tasks require matching language constructs, nested relationships, or code patterns that plain-text search cannot express reliably.";
  };

  pptx = {
    root = anthropic-skills.outPath + "/skills/pptx";
    customization.body =
      { original, ... }:
      ''

        > **Local override**: run shell commands in this skill through the
        > declarative PPTX tool environment:
        >
        > `nix run dotfiles#pptx -- <command>`
        >
        > Examples:
        >
        > `nix run dotfiles#pptx -- python -m markitdown input.pptx`
        > `nix run dotfiles#pptx -- pdftoppm -jpeg -r 150 output.pdf slide`
        >
        > Helper scripts such as `python scripts/thumbnail.py ...` are also
        > resolved from the installed `/pptx` skill when the current project
        > does not have its own `scripts/` directory.
      ''
      + original;
  };

  frontend-design = {
    root = anthropic-skills.outPath + "/skills/frontend-design";
  };

  drawio = {
    root = drawio-skill.outPath + "/plugins/claude-code/skills/drawio";
    customization.body =
      { original, ... }:
      ''

        > **Local override (WSL2)**: use `drawio` from `$PATH` for exports —
        > it is a Linux headless wrapper that already injects `--no-sandbox`,
        > `--disable-gpu`, and starts Xvfb / D-Bus. Do not add these flags or
        > call `/mnt/c/.../draw.io.exe` for the export step; the "Opening the
        > result" instructions below still apply.
      ''
      + original;
  };

  improve = {
    root = improve-skill.outPath + "/skills/improve";
  };
}
