{ lib, pkgs }:
let
  fakeGhq = pkgs.writeShellApplication {
    name = "ghq";
    text = ''printf '%s\n' /tmp/repo'';
  };
  fakeGit = pkgs.writeShellApplication {
    name = "git";
    text = "exit 0";
  };
  package = pkgs.callPackage ../_packages/fetch-all {
    ghq = fakeGhq;
    git = fakeGit;
  };
  smoke = pkgs.runCommand "ghq-fetch-all-smoke" { } ''
    PATH=/nonexistent ${lib.getExe package}
    touch "$out"
  '';
in
{
  owner = "ghq-fetch-all package smoke";
  artifacts = [
    {
      name = "ghq-fetch-all";
      path = smoke;
    }
  ];
  buildEntries = { };
}
