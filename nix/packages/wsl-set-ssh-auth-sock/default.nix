{
  gnupg,
  systemd,
  writeShellApplication,
}:
writeShellApplication {
  name = "set-SSH_AUTH_SOCK-wsl";
  text = ''
    GPGCONF_BIN=${gnupg}/bin/gpgconf
    SYSTEMCTL_BIN=${systemd}/bin/systemctl
    ${builtins.readFile ./set-ssh-auth-sock.sh}
  '';
}
