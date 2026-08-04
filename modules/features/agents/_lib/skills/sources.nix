# デプロイ対象 skill の宣言。root は SKILL.md を含むディレクトリ。
# customization (任意) で frontmatter / body / invocation policy を変更する。
{ inputs }:
let
  inherit (inputs)
    ax
    ast-grep-skill
    agent-browser-skill
    agent-slack-skill
    anthropic-skills
    difit-src
    drawio-skill
    hunk
    improve-skill
    ;
in
{
  ax = {
    root = ax.outPath + "/skills/ax";
  };

  ast-grep = {
    root = ast-grep-skill.outPath + "/ast-grep/skills/ast-grep";
    customization.frontmatter.description = "Performs syntax-aware structural code search when tasks require matching language constructs, nested relationships, or code patterns that plain-text search cannot express reliably.";
  };

  agent-browser = {
    root = agent-browser-skill.outPath + "/skills/agent-browser";
    customization.frontmatter.inheritFields = [ "hidden" ];
    customization.frontmatter.excludeFields = [ "allowed-tools" ];
    customization.frontmatter.description = "Controls headless browser sessions through the agent-browser CLI when tasks require scripted navigation, form filling, clicks, authentication, screenshots, data extraction, or web application testing.";
  };

  # バイナリ本体は packages/agent-slack (skill doc とは別 input)
  agent-slack = {
    root = agent-slack-skill.outPath + "/skills/agent-slack";
    # Keep skill descriptions compact because some metadata consumers impose
    # length limits; avoid a separate trigger-word list unless it adds signal.
    customization.frontmatter.description = ''
      Slack automation CLI for AI agents. Use when the user asks to read,
      search, send, reply to, edit, delete, or react to Slack messages;
      inspect threads, channels, DMs, unread messages, saved-for-later items,
      files, canvases, users, or workflows; upload local files to Slack; or
      manage channels and conversations.
    '';
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

  difit = {
    root = difit-src.outPath + "/skills/difit";
    customization.disableAutomaticInvocation = true;
  };

  difit-review = {
    root = difit-src.outPath + "/skills/difit-review";
    customization.disableAutomaticInvocation = true;
  };

  hunk-review = {
    root = hunk.outPath + "/skills/hunk-review";
  };

  improve = {
    root = improve-skill.outPath + "/skills/improve";
  };
}
