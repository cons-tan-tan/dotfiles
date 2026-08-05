{ pkgs }:
let
  package = pkgs.dotfilesPackages.agent-browser;
  smoke = pkgs.runCommand "agent-browser-smoke" { nativeBuildInputs = [ package ]; } ''
    agent-browser --version > /dev/null
    touch "$out"
  '';
in
{
  owner = "agent-browser package smoke";
  artifacts = [
    {
      name = "agent-browser";
      path = smoke;
    }
  ];
  checks = { };
}
