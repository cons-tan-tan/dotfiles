{ pkgs }:
let
  package = pkgs.dotfilesPackages.difit;
  smoke = pkgs.runCommand "difit-smoke" { nativeBuildInputs = [ package ]; } ''
    test "$(difit --version)" = "${package.version}"
    difit --help > /dev/null
    touch "$out"
  '';
in
{
  owner = "difit package smoke";
  artifacts = [
    {
      name = "difit";
      path = smoke;
    }
  ];
  buildEntries = { };
}
