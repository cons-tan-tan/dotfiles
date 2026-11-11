{ lib }:
let
  original = import ./skill-fixture.nix;
  transform =
    text:
    import ../_lib/transform-skill.nix {
      inherit lib;
      original = text;
    };
  extra = "\n## Newly added guidance\nKeep this content.\n";
in
{
  testPreservesGuidanceAndVersionWhileChangingRuntime = {
    expr = {
      search = lib.hasInfix "modern-web-guidance search \"dialog\" --skill-version 2026_11_09-example" (
        transform original
      );
      retrieve = lib.hasInfix "modern-web-guidance retrieve \"dialog\"" (transform original);
      runtime = lib.hasInfix "managed together by Nix" (transform original);
      guidance = builtins.elemAt (lib.splitString "## Browser guidance" (transform original)) 1;
    };
    expected = {
      search = true;
      retrieve = true;
      runtime = true;
      guidance = builtins.elemAt (lib.splitString "## Browser guidance" original) 1;
    };
  };
  testAcceptsNewGuidanceAndAdditionalInvocations = {
    expr = lib.hasSuffix ("\nmodern-web-guidance list\n" + extra) (
      transform (original + "\nnpx -y modern-web-guidance@latest list\n" + extra)
    );
    expected = true;
  };
  testAcceptsPreviousRunnerHeading = {
    expr = transform (builtins.replaceStrings [ "Using npx / pnpx" ] [ "Using npx" ] original);
    expected = transform original;
  };
}
