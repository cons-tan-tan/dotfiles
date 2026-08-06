{ pkgs }:
let
  package = pkgs.dotfilesPackages.claude-code.package;
in
{
  testClaudeCodePackageOwnsSettingsSchemaUpdateScript = {
    expr =
      builtins.isString package.updateScript && package.updateScriptName == "claude-code-settings-schema";
    expected = true;
  };
}
