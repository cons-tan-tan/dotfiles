{ config, ... }:
{
  flake.modules.homeManager.platform-wsl-nixbuild = {
    key = "modules/features/platform/wsl/nixbuild.nix#homeManager.platform-wsl-nixbuild";
    imports = [
      config.flake.modules.homeManager.security-gpg-wsl
    ];
  };

  flake.modules.nixos.platform-wsl-nixbuild =
    { config, ... }:
    let
      username = config.wsl.defaultUser;
      uid = config.users.users.${username}.uid;
    in
    {
      key = "modules/features/platform/wsl/nixbuild.nix#nixos.platform-wsl-nixbuild";

      # Distributed builds run as root, so explicitly expose the existing
      # user GPG agent instead of provisioning a separate private key.
      systemd.services.nix-daemon.environment.SSH_AUTH_SOCK =
        "/run/user/${toString uid}/gnupg/S.gpg-agent.ssh";

      # nix-daemon uses the system SSH configuration, not the user's
      # Home Manager configuration. nixbuild.net recommends keepalives
      # and the legacy "throughput" QoS value, but OpenSSH 10.1+ ignores
      # that value. Leave DSCP marking to the OS explicitly instead.
      programs.ssh.extraConfig = ''
        Host eu.nixbuild.net
            PubkeyAcceptedAlgorithms ssh-ed25519
            ServerAliveInterval 60
            IPQoS none
      '';
    };
}
