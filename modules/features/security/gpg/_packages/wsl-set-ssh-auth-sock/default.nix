{
  gnupg,
  lib,
  systemd,
  writeShellApplication,
  gpgconfBin ? "${gnupg}/bin/gpgconf",
  systemctlBin ? "${systemd}/bin/systemctl",
}:
writeShellApplication {
  name = "set-SSH_AUTH_SOCK-wsl";
  text = ''
    GPGCONF_BIN=${lib.escapeShellArg gpgconfBin}
    SYSTEMCTL_BIN=${lib.escapeShellArg systemctlBin}
    ${builtins.readFile ./set-ssh-auth-sock.sh}
  '';
}
