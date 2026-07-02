{ darwinHostname }:
pkgs:
let
  inherit (pkgs.lib) escapeShellArg;

  buildScript = pkgs.writeShellApplication {
    name = "darwin-build";
    text = ''
      export DARWIN_HOSTNAME=${escapeShellArg darwinHostname}
      ${builtins.readFile ../apps/darwin-build.sh}
    '';
  };

  switchScript = pkgs.writeShellApplication {
    name = "darwin-switch";
    text = ''
      export DARWIN_HOSTNAME=${escapeShellArg darwinHostname}
      ${builtins.readFile ../apps/darwin-switch.sh}
    '';
  };
in
{
  apps = {
    build = {
      type = "app";
      meta.description = "Build the nix-darwin configuration without activating it";
      program = pkgs.lib.getExe buildScript;
    };
    switch = {
      type = "app";
      meta.description = "Build and activate the nix-darwin configuration";
      program = pkgs.lib.getExe switchScript;
    };
  };

  scripts = [
    buildScript
    switchScript
  ];
}
