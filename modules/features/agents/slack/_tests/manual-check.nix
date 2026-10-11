{ pkgs }:
let
  package = pkgs.dotfilesPackages.agent-slack;
  smoke = pkgs.runCommand "agent-slack-smoke" { nativeBuildInputs = [ package ]; } ''
    # バンドルを失ったバイナリも素の bun として --version に成功するため、値まで比較する。
    test "$(agent-slack --version)" = ${pkgs.lib.escapeShellArg package.version}
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
  buildEntries = { };
}
