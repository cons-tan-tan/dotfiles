{
  pkgs,
  standard,
  scopes ? import ../../_data/commit-profile-scopes.nix,
}:
let
  inherit (pkgs) lib;
  payload = import ../../_interface/payload.nix;
  mkSkillSource = import ../../_lib/mk-skill-source.nix { inherit pkgs; };
  fineGrained = mkSkillSource {
    name = "commit";
    provenance = "local";
    definition = {
      root = standard;
      customization = {
        frontmatter.description = "Creates fine-grained Conventional Commits. Use when committing changes, splitting a diff into commits, or drafting commit messages.";
        body = {
          program = ../../_lib/fine-grained-commit.nix;
          arguments.granularity = builtins.readFile payload.fineGrainedCommit;
        };
      };
    };
  };
  variants = {
    inherit standard;
    fine-grained = fineGrained;
  };
  artifacts = pkgs.runCommand "commit-skill-profiles" { } (
    lib.concatMapStringsSep "\n" (
      profile:
      let
        override = "skills.config=[{path=\"${standard}/SKILL.md\",enabled=${
          lib.boolToString (profile == "standard")
        }},{path=\"${fineGrained}/SKILL.md\",enabled=${lib.boolToString (profile == "fine-grained")}}]";
      in
      ''
        mkdir -p "$out/${profile}/.claude/skills"
        ln -s ${variants.${profile}} "$out/${profile}/.claude/skills/commit"
        printf '%s\n' ${lib.escapeShellArg override} > "$out/${profile}/codex-override"
      ''
    ) (builtins.attrNames variants)
  );
  selector = pkgs.writeShellApplication {
    name = "agent-skill-profile";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.git
      pkgs.ghq
    ];
    text = ''
      PROFILE_SCOPES=(${lib.escapeShellArgs scopes})
      ${builtins.readFile ./select-profile.sh}
    '';
  };
in
{
  inherit
    standard
    fineGrained
    artifacts
    selector
    ;
}
