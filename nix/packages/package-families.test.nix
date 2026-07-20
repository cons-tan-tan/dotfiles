{ pkgs }:
let
  inherit (pkgs.dotfilesPackages)
    codex
    hcom
    herdr
    hunk
    ;
in
{
  testCodexFamilyShape = {
    expr = builtins.attrNames codex;
    expected = [ "mkWrappedPackage" ];
  };

  testCodexWrapperIsBuilder = {
    expr = builtins.isFunction codex.mkWrappedPackage;
    expected = true;
  };

  testCodexWrapperBuildsDerivation = {
    expr = pkgs.lib.isDerivation (
      codex.mkWrappedPackage {
        herdrSkillPath = "/home/test/.codex/skills/herdr/SKILL.md";
      }
    );
    expected = true;
  };

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
      "wrappedPackage"
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

  testHerdrPackagesAreDerivations = {
    expr = builtins.all pkgs.lib.isDerivation [
      herdr.package
      herdr.wrappedPackage
    ];
    expected = true;
  };

  testHunkFamilyShape = {
    expr = builtins.attrNames hunk;
    expected = [
      "package"
      "wslRuntime"
    ];
  };

  testHunkPackagesAreDerivations = {
    expr = builtins.all pkgs.lib.isDerivation [
      hunk.package
      hunk.wslRuntime
    ];
    expected = true;
  };
}
