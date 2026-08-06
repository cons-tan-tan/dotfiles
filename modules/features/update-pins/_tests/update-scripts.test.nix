{ pkgs }:
let
  scripts = import ../_interface/update-scripts.nix { inherit pkgs; };
in
{
  testPackageOwnedUpdateScriptRegistryIsNonEmpty = {
    expr = scripts != { };
    expected = true;
  };

  testPackageOwnedUpdateScriptsHaveExecutableCommands = {
    expr = builtins.all (
      entry:
      builtins.isList entry.command
      && entry.command != [ ]
      && builtins.all builtins.isString entry.command
      && builtins.isString entry.description
      && entry.description != ""
    ) (builtins.attrValues scripts);
    expected = true;
  };
}
