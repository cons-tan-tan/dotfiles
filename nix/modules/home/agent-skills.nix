# Agent skills deployment for Claude Code and other agents.
#
# Skills (external flake inputs + local agents/skills/) are bundled and
# symlinked into ~/.claude/skills and ~/.agents/skills.
#
# NOTE: 以前は agent-skills-nix (flake input) を使っていたが、同モジュールは
# ソースの safe-copy derivation を eval 時に readFile する (IFD) ため、異種
# プラットフォーム構成の評価 (nix flake check 等) を壊す。必要な機能は
# 「skill ディレクトリを集め、SKILL.md を変換して配置する」だけなので自前で
# 実装する。eval 時に読むのは flake input / リポジトリ内の純パスのみ。
{
  lib,
  pkgs,
  inputs,
  ...
}:
let
  inherit (inputs)
    ast-grep-skill
    agent-browser-skill
    agent-slack-skill
    anthropic-skills
    drawio-skill
    hcom-src
    humanizer-jp-skill
    ;

  # SKILL.md を YAML frontmatter と本文に分ける。frontmatter が無い場合は
  # 全体を本文として扱う。
  splitFrontmatter =
    text:
    let
      parts = lib.splitString "\n---\n" text;
      hasFm = builtins.length parts > 1 && lib.hasPrefix "---\n" text;
    in
    {
      frontmatter = if hasFm then builtins.head parts + "\n---\n" else "";
      body = if hasFm then lib.concatStringsSep "\n---\n" (builtins.tail parts) else text;
    };

  replaceFrontmatter = frontmatter: original: frontmatter + (splitFrontmatter original).body;

  injectAfterFrontmatter =
    note: original:
    let
      s = splitFrontmatter original;
    in
    s.frontmatter + note + s.body;

  # 外部 skill。root は SKILL.md を含むディレクトリ。
  externalSkills = {
    # ast-grep official skill
    ast-grep = {
      root = "${ast-grep-skill}/ast-grep/skills/ast-grep";
    };

    # agent-browser skill
    agent-browser = {
      root = "${agent-browser-skill}/skills/agent-browser";
    };

    # agent-slack skill (binary packaged in overlays/agent-slack.nix)
    agent-slack = {
      root = "${agent-slack-skill}/skills/agent-slack";
      # Keep skill descriptions compact because some metadata consumers impose
      # length limits; avoid a separate trigger-word list unless it adds signal.
      transform = replaceFrontmatter ''
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
    };

    # Anthropic official pptx skill
    pptx = {
      root = "${anthropic-skills}/skills/pptx";
      transform = injectAfterFrontmatter ''

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
    };

    # draw.io skill
    drawio = {
      root = "${drawio-skill}/skill-cli/drawio";
      transform = injectAfterFrontmatter ''

        > **Local override (WSL2)**: use `drawio` from `$PATH` for exports —
        > it is a Linux headless wrapper that already injects `--no-sandbox`,
        > `--disable-gpu`, and starts Xvfb / D-Bus. Do not add these flags or
        > call `/mnt/c/.../draw.io.exe` for the export step; the "Opening the
        > result" instructions below still apply.
      '';
    };

    # hcom inter-agent messaging skill (binary packaged in overlays/hcom.nix)
    hcom-agent-messaging = {
      root = "${hcom-src}/skills/hcom-agent-messaging";
    };

    # humanize-jp skill (suppress "AI-ness" in Japanese writing)
    humanize-jp = {
      root = "${humanizer-jp-skill}/.claude/skills/humanize-jp";
      # Upstream's command assumes a system python3 and $HOME as the cwd, and
      # references docs/ at the repo root (outside the skill dir, so the
      # deployed copy would have dangling links).
      #   - uv run drops the python3 dependency; --no-project keeps uv from
      #     syncing whatever caller project we land in (script is stdlib-only).
      #   - Script and docs are pointed at the flake input's store path: it is
      #     absolute (stable from any cwd / both ~/.agents and ~/.claude
      #     targets) and the reference keeps the source in the closure.
      transform =
        original:
        replaceFrontmatter
          ''
            ---
            name: humanize-jp
            description: |
              Suppress the telltale "AI-ness" of Japanese writing so it reads as
              human-written. Use when asked to proofread or rewrite AI-generated
              Japanese, make text sound more natural, or polish note and blog
              articles. Japanese only; not for English or other languages.
            ---
          ''
          (
            builtins.replaceStrings
              [
                "python3 .claude/skills/humanize-jp/reference/humanize_check.py"
                "`docs/"
              ]
              [
                "uv run --no-project ${humanizer-jp-skill}/.claude/skills/humanize-jp/reference/humanize_check.py"
                "`${humanizer-jp-skill}/docs/"
              ]
              original
          );
    };
  };

  # このリポジトリの agents/skills/ 配下は全て自動デプロイする
  localSkillsDir = ../../../agents/skills;
  localSkills = lib.mapAttrs (name: _: { root = localSkillsDir + "/${name}"; }) (
    lib.filterAttrs (_: type: type == "directory") (builtins.readDir localSkillsDir)
  );

  skills = externalSkills // localSkills;

  # transform がある skill は SKILL.md を差し替えたコピーを作る。無ければ
  # ソースをそのまま symlink する。
  mkSkillSource =
    name: skill:
    if skill ? transform then
      pkgs.runCommandLocal "skill-${name}"
        {
          skillMd = skill.transform (builtins.readFile (skill.root + "/SKILL.md"));
          passAsFile = [ "skillMd" ];
        }
        ''
          cp -rL --no-preserve=mode ${skill.root} $out
          cp "$skillMdPath" "$out/SKILL.md"
        ''
    else
      skill.root;

  skillSources = lib.mapAttrs mkSkillSource skills;

  deployTo =
    prefix:
    lib.mapAttrs' (
      name: source: lib.nameValuePair "${prefix}/${name}" { inherit source; }
    ) skillSources;
in
{
  home.file = deployTo ".claude/skills" // deployTo ".agents/skills";
}
