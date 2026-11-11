{ ciCheck, pkgs }:
let
  package = pkgs.dotfilesPackages.modern-web-guidance;
  testSource = pkgs.lib.fileset.toSource {
    root = ../.;
    fileset = pkgs.lib.fileset.unions [
      ./rewrite-references.test.mjs
      ../_packages/modern-web-guidance/rewrite-references.mjs
    ];
  };
  skill = (import ../../skills/_lib/mk-skill-source.nix { inherit pkgs; }) {
    name = "modern-web-guidance";
    provenance = "external";
    definition = {
      root = package.skillRoot;
      customization.body.program = ../_lib/transform-skill.nix;
    };
  };
in
{
  owner = "Modern Web Guidance runtime and skill adaptation";
  artifacts = [ ];
  buildEntries.modern-web-guidance = ciCheck.buildEntry (ciCheck.targets.both "package-smoke") (
    pkgs.runCommand "modern-web-guidance-check" { nativeBuildInputs = [ pkgs.nodejs ]; } ''
      node ${testSource}/_tests/rewrite-references.test.mjs
      test -s ${skill}/SKILL.md
      test -x ${package}/bin/modern-web-guidance
      touch "$out"
    ''
  );
}
