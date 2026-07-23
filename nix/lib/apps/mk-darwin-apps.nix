{
  inputs,
  darwinHostname,
}:
{ system, pkgs }:
let
  inherit (pkgs.lib) escapeShellArg;
  appSet = import ./mk-app-set.nix { lib = pkgs.lib; };
  darwinRebuild = "${inputs.nix-darwin.packages.${system}.darwin-rebuild}/bin/darwin-rebuild";

  buildScript = pkgs.writeShellApplication {
    name = "darwin-build";
    text = ''
      export DARWIN_HOSTNAME=${escapeShellArg darwinHostname}
      ${builtins.readFile ../../apps/darwin-build.sh}
    '';
  };

  switchScript = pkgs.writeShellApplication {
    name = "darwin-switch";
    text = ''
      export DARWIN_HOSTNAME=${escapeShellArg darwinHostname}
      export DARWIN_REBUILD_BIN=${escapeShellArg darwinRebuild}
      ${builtins.readFile ../../apps/darwin-switch.sh}
    '';
  };
in
appSet.mkAppSet {
  entries = {
    build = {
      description = "Build the nix-darwin configuration without activating it";
      script = buildScript;
    };
    switch = {
      description = "Build and activate the nix-darwin configuration";
      script = switchScript;
    };
  };
}
