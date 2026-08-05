{ lib, pkgs }:
let
  lock = import ../_lib/cleanup-lock.nix {
    coreutils = pkgs.coreutils;
    inherit lib;
    username = "test-user";
  };
in
{
  testCleanupLockUsesDedicatedRuntimeDirectory = {
    expr = {
      inherit (lock) cleanupFile directory installerFile;
      preparationCount = builtins.length lock.preparationCommands;
      preparationUsesDedicatedDirectory = builtins.all (
        command: lib.hasInfix lock.directory command && !lib.hasInfix "/run/lock" command
      ) lock.preparationCommands;
    };
    expected = {
      directory = "/run/nh-cleanup-systemd";
      cleanupFile = "/run/nh-cleanup-systemd/cleanup.lock";
      installerFile = "/run/nh-cleanup-systemd/installer.lock";
      preparationCount = 4;
      preparationUsesDedicatedDirectory = true;
    };
  };
}
