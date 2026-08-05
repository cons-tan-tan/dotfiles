{
  appSet,
  darwinHostname,
}:
{
  darwinRebuildBin,
  pkgs,
}:
let
  inherit (pkgs.lib) escapeShellArg;
  buildScript = pkgs.writeShellApplication {
    name = "darwin-build";
    text = ''
      export DARWIN_HOSTNAME=${escapeShellArg darwinHostname}
      ${builtins.readFile ../_scripts/darwin-build.sh}
    '';
  };

  switchScript = pkgs.writeShellApplication {
    name = "darwin-switch";
    text = ''
      export DARWIN_HOSTNAME=${escapeShellArg darwinHostname}
      export DARWIN_REBUILD_BIN=${escapeShellArg darwinRebuildBin}
      ${builtins.readFile ../_scripts/darwin-switch.sh}
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
