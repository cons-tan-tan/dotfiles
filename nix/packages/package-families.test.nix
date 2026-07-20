{ pkgs }:
let
  inherit (pkgs.dotfilesPackages) hcom herdr;
in
{
  testHcomFamilyShape = {
    expr = builtins.attrNames hcom;
    expected = [
      "integrations"
      "package"
    ];
  };

  testHcomIntegrationShape = {
    expr = builtins.attrNames hcom.integrations;
    expected = [
      "claudeHooks"
      "codexHooks"
    ];
  };

  testHcomPackageIsDerivation = {
    expr = pkgs.lib.isDerivation hcom.package;
    expected = true;
  };

  testHerdrFamilyShape = {
    expr = builtins.attrNames herdr;
    expected = [
      "agent"
      "integrations"
      "package"
    ];
  };

  testHerdrAgentShape = {
    expr = builtins.attrNames herdr.agent;
    expected = [
      "codexMarketplace"
      "plugin"
      "skill"
    ];
  };

  testHerdrIntegrationShape = {
    expr = builtins.attrNames herdr.integrations;
    expected = [
      "claude"
      "codex"
      "opencode"
      "pi"
    ];
  };

  testHerdrPackageIsDerivation = {
    expr = pkgs.lib.isDerivation herdr.package;
    expected = true;
  };
}
