{ pkgs }:
let
  inherit (pkgs) lib;
  libPath = builtins.path {
    name = "nixpkgs-lib";
    path = pkgs.path + "/lib";
  };
  compilerPath = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ./render-skill.nix
      ./skill-policy.nix
      ./yaml-frontmatter.nix
      ../_data/policy.nix
    ];
  };
in
{
  definition,
  name,
  provenance,
}:
let
  customization = definition.customization or { };
  manifest = builtins.toJSON {
    inherit name;
    root = definition.root;
    requireExplicitFieldDecisions = provenance != "local";
    body = customization.body or null;
    customization = removeAttrs customization [ "body" ];
  };
in
pkgs.runCommandLocal "skill-${name}"
  {
    inherit manifest;
    passAsFile = [ "manifest" ];
    skillRoot = definition.root;
    nativeBuildInputs = [
      (lib.getBin pkgs.buildPackages.nix)
      pkgs.buildPackages.yq-go
    ];
  }
  ''
    set -euo pipefail
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"

    rendered="$TMPDIR/rendered"
    nix --extra-experimental-features nix-command eval \
      --impure \
      --offline \
      --store dummy:// \
      --option allow-import-from-derivation false \
      --write-to "$rendered" \
      --file ${compilerPath}/_lib/render-skill.nix \
      output \
      --argstr manifestPath "$manifestPath" \
      --argstr libPath ${libPath} \
      --argstr policyPath ${compilerPath}/_data/policy.nix \
      --argstr skillPolicyPath ${compilerPath}/_lib/skill-policy.nix

    cp -rL --no-preserve=mode "$skillRoot" "$out"
    cp -rL --no-preserve=mode "$rendered/." "$out/"
    ${lib.optionalString (customization.disableAutomaticInvocation or false) ''
      mkdir -p "$out/agents"
      touch "$out/agents/openai.yaml"
      # Codex does not expand YAML merge keys. Resolve aliases before replacing
      # policy so shared anchors keep their original values elsewhere.
      yq --yaml-fix-merge-anchor-to-spec=true -i \
        'explode(.) | . + {"policy": ((.policy // {}) * {"allow_implicit_invocation": false})}' \
        "$out/agents/openai.yaml"
    ''}
  ''
