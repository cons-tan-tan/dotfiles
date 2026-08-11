{
  config,
  lib,
  pkgs,
  username,
}:
let
  home = config.home-manager.users.${username};
  actual = {
    systemNixEnabled = config.nix.enable;
    systemNixGcAutomatic = config.nix.gc.automatic;
    systemNixGcDaemonDefined = config.launchd.daemons ? nix-gc;
    homeNixGcAutomatic = home.nix.gc.automatic;
    homeNixGcAgentDefined = home.launchd.agents ? nix-gc;
    homeNhCleanupEnabled = home.programs.nh.clean.enable;
    homeNhCleanupAgentDefined = home.launchd.agents ? nh-clean;
  };
  expected = {
    systemNixEnabled = false;
    systemNixGcAutomatic = false;
    systemNixGcDaemonDefined = false;
    homeNixGcAutomatic = false;
    homeNixGcAgentDefined = false;
    homeNhCleanupEnabled = false;
    homeNhCleanupAgentDefined = false;
  };
in
assert lib.assertMsg (actual == expected) ''
  Darwin Nix cleanup ownership contract mismatch:
  expected ${builtins.toJSON expected}
  actual ${builtins.toJSON actual}
'';
pkgs.runCommand "darwin-nh-cleanup-contract" { } ''touch "$out"''
