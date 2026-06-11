# Agent skills configuration for Claude Code
# https://github.com/Kyure-A/agent-skills-nix
#
# All skills (external and local) are managed here via agent-skills-nix.
# Skills are deployed to ~/.claude/skills and ~/.agents/skills
{
  lib,
  pkgs,
  ast-grep-skill,
  agent-browser-skill,
  agent-slack-skill,
  anthropic-skills,
  drawio-skill,
  hcom-src,
  humanizer-jp-skill,
  ...
}:
let
  # docs/ sits at the repo root, outside the skill dir, so feeding
  # humanizer-jp-skill straight to the source would leave SKILL.md's docs/ links
  # dangling.
  humanizer-jp-with-docs = pkgs.runCommandLocal "humanizer-jp-with-docs" { } ''
    skill="$out/.claude/skills/humanize-jp"
    mkdir -p "$skill"
    cp -r ${humanizer-jp-skill}/.claude/skills/humanize-jp/. "$skill/"
    cp -r ${humanizer-jp-skill}/docs "$skill/docs"
    mkdir -p "$skill/scripts"
    cp "$skill/reference/humanize_check.py" "$skill/scripts/humanize_check.py"
  '';
in
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
      # External: hcom inter-agent messaging skill (binary packaged in overlays/hcom.nix)
      hcom = {
        path = hcom-src;
        subdir = "skills";
      };
      # External: humanize-jp skill (suppress "AI-ness" in Japanese writing)
      humanizer-jp = {
        path = humanizer-jp-with-docs;
        subdir = ".claude/skills";
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
      transform =
        { original, ... }:
        let
          parts = lib.splitString "\n---\n" original;
          hasFm = builtins.length parts > 1 && lib.hasPrefix "---\n" original;
          frontmatter = if hasFm then builtins.head parts + "\n---\n" else "";
          body = if hasFm then lib.concatStringsSep "\n---\n" (builtins.tail parts) else original;
          override = ''

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
          '';
        in
        frontmatter + override + body;
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

    skills.explicit.hcom-agent-messaging = {
      from = "hcom";
      path = "hcom-agent-messaging";
    };

    skills.explicit.humanize-jp = {
      from = "humanizer-jp";
      path = "humanize-jp";
      transform =
        { original, ... }:
        let
          # Upstream's command assumes a system python3 and $HOME as the cwd.
          #   - uv run drops the python3 dependency; --no-project keeps uv from
          #     syncing whatever caller project we land in (script is stdlib-only).
          #   - The final Nix store bundle is shared by ~/.agents and ~/.claude
          #     targets, so an absolute bundle path is stable from any cwd.
          humanizeCheck = "${builtins.placeholder "out"}/humanize-jp/scripts/humanize_check.py";
          rewritten =
            builtins.replaceStrings
              [ "python3 .claude/skills/humanize-jp/reference/humanize_check.py" ]
              [ "uv run --no-project ${humanizeCheck}" ]
              original;
          parts = lib.splitString "\n---\n" rewritten;
          hasFm = builtins.length parts > 1 && lib.hasPrefix "---\n" rewritten;
          body = if hasFm then lib.concatStringsSep "\n---\n" (builtins.tail parts) else rewritten;
          frontmatter = ''
            ---
            name: humanize-jp
            description: |
              Suppress the telltale "AI-ness" of Japanese writing so it reads as
              human-written. Use when asked to proofread or rewrite AI-generated
              Japanese, make text sound more natural, or polish note and blog
              articles. Japanese only; not for English or other languages.
            ---
          '';
        in
        frontmatter + body;
    };

    # Deploy to skills directories (use built-in default paths)
    targets = {
      agents.enable = true;
      claude.enable = true;
    };
  };
}
