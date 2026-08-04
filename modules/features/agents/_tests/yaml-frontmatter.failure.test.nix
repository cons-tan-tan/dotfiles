{
  caseName,
  nixpkgsPath,
  repoRoot,
}:
let
  lib = import (nixpkgsPath + "/lib");
  fm = import (repoRoot + "/modules/features/agents/_lib/skills/yaml-frontmatter.nix") {
    inherit lib;
  };
  cases = {
    rejectsUnterminatedFrontmatter = {
      expression = fm.splitFrontmatter "---\nname: demo\nbody\n";
      expectedFragment = "unterminated skill frontmatter";
    };

    rejectsUnsupportedTopLevelSyntax = {
      expression = fm.frontmatterFieldNames ''
        ---
        name: demo
        description: Demo.
        <<: *defaults
        ---
        body
      '';
      expectedFragment = "skill frontmatter contains unsupported top-level syntax";
    };
  };
in
if caseName == null then cases else cases.${caseName}.expression
