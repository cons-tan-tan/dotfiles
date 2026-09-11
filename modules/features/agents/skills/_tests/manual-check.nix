{
  ciCheck,
  pkgs,
  ...
}:
let
  mkSkillSource = import ../_lib/mk-skill-source.nix { inherit pkgs; };
  sourceSkillMd = pkgs.writeText "agent-skill-renderer-source.md" ''
    ---
    name: demo
    description: Original description.
    allowed-tools: Bash(example:*)
    ---
    old body
  '';
  sourceOpenaiYaml = pkgs.writeText "agent-skill-renderer-source-openai.yaml" ''
    interface:
      display_name: Demo
    policy:
      allow_implicit_invocation: true
  '';
  source = pkgs.runCommand "agent-skill-renderer-source" { } ''
    mkdir -p "$out/agents"
    cp ${sourceSkillMd} "$out/SKILL.md"
    cp ${sourceOpenaiYaml} "$out/agents/openai.yaml"
  '';
  rendered = mkSkillSource {
    name = "demo";
    provenance = "external";
    definition = {
      root = source;
      customization = {
        frontmatter = {
          description = "Rendered description.";
          excludeFields = [ "allowed-tools" ];
        };
        body = {
          program = ./fixtures/body-transformers/demo;
          arguments = {
            prefix = "NOTE\n";
            from = "old";
            to = "new";
          };
        };
        disableAutomaticInvocation = true;
      };
    };
  };
  expectedSkillMd = pkgs.writeText "agent-skill-renderer-expected.md" ''
    ---
    disable-model-invocation: true
    name: demo
    description: "Rendered description."
    ---
    NOTE
    new body
  '';
  expectedOpenaiYaml = pkgs.writeText "agent-skill-renderer-expected-openai.yaml" ''
    interface:
      display_name: Demo
    policy:
      allow_implicit_invocation: false
  '';
in
{
  owner = "agent skill renderer checks";
  artifacts = [ ];
  buildEntries.agent-skill-renderer = ciCheck.buildEntry (ciCheck.targets.both "eval-tests") (
    pkgs.runCommand "agent-skill-renderer-check" { } ''
      cmp ${expectedSkillMd} ${rendered}/SKILL.md
      cmp ${expectedOpenaiYaml} ${rendered}/agents/openai.yaml
      touch "$out"
    ''
  );
}
