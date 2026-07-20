# デプロイ対象 skill の定義。root は SKILL.md を含むディレクトリ、transform
# (任意) は SKILL.md 全文を受け取り書き換える関数。
# additionalInheritedFrontmatterFields (任意) で default policy にない
# upstream field をskill単位で明示的に許可する。
{ lib, inputs }:
let
  inherit (inputs)
    ast-grep-skill
    agent-browser-skill
    agent-slack-skill
    anthropic-skills
    difit-src
    drawio-skill
    hcom-src
    hunk
    humanizer-jp-skill
    improve-skill
    ;

  inherit (import ./frontmatter.nix { inherit lib; })
    replaceFrontmatter
    setFrontmatterField
    injectAfterFrontmatter
    ;

  # モデルの判断による自動呼び出しを止め、ユーザーの明示呼び出しだけ許す
  # skill。Codex/Pi/Claude Code 向けの具体的な配置は default.nix で行う。
  automaticInvocationDisabledSkills = [
    "difit"
    "difit-review"
  ];

  externalSkills = {
    ast-grep = {
      root = "${ast-grep-skill}/ast-grep/skills/ast-grep";
    };

    agent-browser = {
      root = "${agent-browser-skill}/skills/agent-browser";
      # Override only discovery wording. The central frontmatter policy keeps
      # safe upstream metadata such as hidden while dropping allowed-tools.
      transform = setFrontmatterField "description" "Controls headless browser sessions through the agent-browser CLI when tasks require scripted navigation, form filling, clicks, authentication, screenshots, data extraction, or web application testing.";
    };

    # バイナリ本体は packages/agent-slack (skill doc とは別 input)
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

    frontend-design = {
      root = "${anthropic-skills}/skills/frontend-design";
    };

    drawio = {
      root = "${drawio-skill}/plugins/claude-code/skills/drawio";
      transform = injectAfterFrontmatter ''

        > **Local override (WSL2)**: use `drawio` from `$PATH` for exports —
        > it is a Linux headless wrapper that already injects `--no-sandbox`,
        > `--disable-gpu`, and starts Xvfb / D-Bus. Do not add these flags or
        > call `/mnt/c/.../draw.io.exe` for the export step; the "Opening the
        > result" instructions below still apply.
      '';
    };

    difit = {
      root = "${difit-src}/skills/difit";
    };

    difit-review = {
      root = "${difit-src}/skills/difit-review";
    };

    # バイナリ本体は overlays/hcom.nix (hcom-src input とは update-pins が同期)
    hcom-agent-messaging = {
      root = "${hcom-src}/skills/hcom-agent-messaging";
    };

    hunk-review = {
      root = "${hunk}/skills/hunk-review";
    };

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

    improve = {
      root = "${improve-skill}/skills/improve";
    };
  };

  # このリポジトリの agents/skills/ 配下は全て自動デプロイする
  localSkillsDir = ../../../../agents/skills;
  localSkills = lib.mapAttrs (name: _: { root = localSkillsDir + "/${name}"; }) (
    lib.filterAttrs (_: type: type == "directory") (builtins.readDir localSkillsDir)
  );

  allSkills = externalSkills // localSkills;
  unknownAutomaticInvocationDisabledSkills = lib.filter (
    name: !(builtins.hasAttr name allSkills)
  ) automaticInvocationDisabledSkills;

  applyInvocationPolicy = lib.mapAttrs (
    name: skill:
    skill
    // lib.optionalAttrs (builtins.elem name automaticInvocationDisabledSkills) {
      disableAutomaticInvocation = true;
    }
  );
in
assert lib.assertMsg (unknownAutomaticInvocationDisabledSkills == [ ])
  "unknown automaticInvocationDisabledSkills entries: ${lib.concatStringsSep ", " unknownAutomaticInvocationDisabledSkills}";
applyInvocationPolicy allSkills
