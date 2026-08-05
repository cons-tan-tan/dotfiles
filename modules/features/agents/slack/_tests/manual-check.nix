{ pkgs }:
let
  package = pkgs.dotfilesPackages.agent-slack;
  smoke = pkgs.runCommand "agent-slack-smoke" { nativeBuildInputs = [ package ]; } ''
    agent-slack --version > /dev/null
    touch "$out"
  '';
in
{
  owner = "agent-slack package smoke";
  artifacts = [
    {
      name = "agent-slack";
      path = smoke;
    }
  ];
  checks = { };
}
