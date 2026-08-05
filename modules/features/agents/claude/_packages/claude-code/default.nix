{
  callPackage,
  claudeCode,
  herdrPlugin,
}:
{
  package = callPackage ./wrapped-package.nix {
    inherit claudeCode herdrPlugin;
  };
}
