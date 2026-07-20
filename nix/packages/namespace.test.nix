{ pkgs }:
let
  local = pkgs.dotfilesPackages;
  commonNames = [
    "agent-browser"
    "agent-slack"
    "difit"
    "hunk"
    "shellfirm"
  ];
  packageValues = (map (name: builtins.getAttr name local) commonNames) ++ [
    local.hcom.package
    local.herdr.package
  ];
in
{
  testPrivateNamespaceExists = {
    expr = pkgs ? dotfilesPackages;
    expected = true;
  };

  testRepresentativePackagesExist = {
    expr = builtins.all (name: builtins.hasAttr name local) commonNames;
    expected = true;
  };

  testRepresentativePackagesAreDerivations = {
    expr = builtins.all pkgs.lib.isDerivation packageValues;
    expected = true;
  };

  testPlatformPackagesAreScoped = {
    expr =
      if pkgs.stdenv.hostPlatform.isLinux then
        local ? drawio-headless && !(local ? codex-app)
      else
        local ? codex-app && !(local ? drawio-headless);
    expected = true;
  };
}
