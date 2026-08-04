{
  coreutils,
  lib,
  username,
}:
let
  directory = "/run/nh-cleanup-systemd";
  cleanupFile = "${directory}/cleanup.lock";
in
{
  inherit cleanupFile directory;
  installerFile = "${directory}/installer.lock";
  preparationCommands = [
    "+${lib.getExe' coreutils "install"} -d -o root -g root -m 0755 ${directory}"
    "+${lib.getExe' coreutils "touch"} ${cleanupFile}"
    "+${lib.getExe' coreutils "chown"} ${username} ${cleanupFile}"
    "+${lib.getExe' coreutils "chmod"} 0600 ${cleanupFile}"
  ];
}
