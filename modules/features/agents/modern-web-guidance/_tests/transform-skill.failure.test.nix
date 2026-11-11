{
  caseName,
  nixpkgsPath,
  repoRoot,
}:
let
  lib = import (nixpkgsPath + "/lib");
  feature = repoRoot + "/modules/features/agents/modern-web-guidance";
  original = import (feature + "/_tests/skill-fixture.nix");
  transform =
    text:
    import (feature + "/_lib/transform-skill.nix") {
      inherit lib;
      original = text;
    };
  cases = {
    changedRunnerSection = {
      expression = transform (
        builtins.replaceStrings [ "## Using npx / pnpx" ] [ "## New runner" ] original
      );
      expectedFragment = "modern-web-guidance: review changed upstream runner section";
    };
    duplicateRunnerSection = {
      expression = transform (original + "\n## Using npx\nOther instructions.\n");
      expectedFragment = "modern-web-guidance: review changed upstream runner section";
    };
    changedInvocation = {
      expression = transform (
        builtins.replaceStrings [ "npx -y modern-web-guidance@latest" ] [ "new-runner" ] original
      );
      expectedFragment = "modern-web-guidance: review changed upstream invocation";
    };
    additionalRunner = {
      expression = transform (original + "\npnpm dlx modern-web-guidance@latest list\n");
      expectedFragment = "modern-web-guidance: unhandled package runner remains";
    };
  };
in
if caseName == null then cases else cases.${caseName}.expression
