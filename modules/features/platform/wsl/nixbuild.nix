{ features, ... }:
{
  features.platform-wsl-nixbuild = {
    name = "feature/platform/wsl/nixbuild";
    includes = [ features.security-gpg-wsl ];
    nixos =
      { config, ... }:
      let
        username = config.wsl.defaultUser;
        uid = config.users.users.${username}.uid;
      in
      {
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
  };
}
