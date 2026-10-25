{
  caseName,
  nixpkgsPath,
  repoRoot,
}:
let
  lib = import (nixpkgsPath + "/lib");
  original = builtins.readFile (repoRoot + "/agents/skills/commit/SKILL.md");
  transform =
    text:
    import ../_lib/fine-grained-commit.nix {
      inherit lib;
      original = text;
      arguments.granularity = "replacement";
    };
  cases = {
    missingAnchor = {
      expression = transform "changed upstream body";
      expectedFragment = "commit profile: expected exactly one granularity anchor";
    };
    repeatedAnchor = {
      expression = transform (original + original);
      expectedFragment = "commit profile: expected exactly one granularity anchor";
    };
  };
in
if caseName == null then cases else cases.${caseName}.expression
