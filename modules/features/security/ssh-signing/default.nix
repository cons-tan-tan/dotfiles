{ ... }:
{
  features.security-ssh-signing = {
    name = "feature/security/ssh-signing";

    homeManager =
      { pkgs, ... }:
      let
        sshenc = pkgs.callPackage ./_packages/sshenc { };
      in
      {
        home.packages = [ sshenc ];

        # allowed_labels limits normal agent use, but is not a per-process authorization boundary.
        xdg.configFile."sshenc/config.toml".text = ''
          allowed_labels = ["git-signing"]
        '';

        # Git invokes sshenc directly, so this does not replace the existing SSH_AUTH_SOCK.
        programs.git = {
          signing = {
            format = "ssh";
            key = "~/.ssh/git-signing.pub";
            signByDefault = true;
            signer = "${sshenc}/bin/sshenc";
          };
          settings.gpg.ssh.allowedSignersFile = "~/.ssh/allowed_signers";
        };

        systemd.user.services.sshenc-agent = {
          Unit.Description = "sshenc agent for TPM-backed signing keys";
          Service = {
            # sshenc-agent creates the socket parent, but not the metadata directory used by first keygen.
            ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p %h/.sshenc/keys";
            ExecStart = "${sshenc}/bin/sshenc-agent --foreground";
            # The CLI proxies through this service, which is the sole Windows bridge caller.
            Environment = [ "SSHENC_BRIDGE_PATH=${sshenc}/bin/sshenc-tpm-bridge.exe" ];
            Restart = "on-failure";
            RestartSec = "1s";
            KillSignal = "SIGINT";
            TimeoutStopSec = "10s";
            UMask = "0077";
            NoNewPrivileges = true;
            PrivateTmp = true;
            ProtectSystem = "full";
          };
          Install.WantedBy = [ "default.target" ];
        };
      };
  };
}
