{ features, ... }:
{
  features.security-oo7-dpapi = {
    name = "feature/security/oo7/dpapi";
    includes = [ features.security-dpapi ];
    nixos =
      { lib, pkgs, ... }:
      let
        bridge = pkgs.dotfilesPackages.oo7-dpapi-bridge;
        helper = pkgs.dotfilesPackages.wsl-dpapi;
        blob = "%S/oo7-dpapi/login-master.dpapi";
        credentialSocket = "%t/oo7-dpapi-credential.sock";
      in
      {
        services.oo7.enable = true;

        # The Login keyring is bound to a random DPAPI-protected secret, not to
        # the WSL login password handled by pam_oo7.
        security.pam.services.login.oo7.enable = lib.mkForce false;

        systemd.user.sockets.oo7-dpapi-credential = {
          description = "On-demand DPAPI credential provider for oo7";
          wantedBy = [ "sockets.target" ];
          socketConfig = {
            ListenStream = credentialSocket;
            SocketMode = "0600";
            Accept = true;
            RemoveOnStop = true;
          };
        };

        systemd.user.services."oo7-dpapi-credential@" = {
          description = "Unprotect the oo7 keyring secret with Windows DPAPI";
          unitConfig.CollectMode = "inactive-or-failed";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${helper}/bin/wsl-dpapi.exe unprotect";
            StandardInput = "file:${blob}";
            StandardOutput = "socket";
            StandardError = "journal";
            UMask = "0077";
            NoNewPrivileges = true;
            TimeoutStartSec = "10s";
          };
        };

        systemd.user.services.oo7-dpapi-prepare = {
          description = "Prepare and verify the DPAPI-bound oo7 Login keyring";
          before = [ "oo7-daemon.service" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${lib.getExe bridge} ${helper}/bin/wsl-dpapi.exe ${blob}";
            # Stay inactive so every oo7-daemon start gets a fresh blob,
            # keyring, and sentinel verification. This cannot be ExecStartPre
            # on oo7-daemon because its upstream PrivateNetwork sandbox would
            # prevent the helper from crossing the WSL interop boundary.
            RemainAfterExit = false;
            UMask = "0077";
            NoNewPrivileges = true;
            TimeoutStartSec = "30s";
          };
        };

        systemd.user.services.oo7-daemon = {
          # Keep the readiness assertion coupled to the daemon without using
          # ExecStartPost. A user manager cannot join that second process to
          # oo7's existing private network namespace.
          bindsTo = [ "oo7-unlock-check.service" ];
          requires = [
            "oo7-dpapi-credential.socket"
            "oo7-dpapi-prepare.service"
          ];
          after = [
            "oo7-dpapi-credential.socket"
            "oo7-dpapi-prepare.service"
          ];
          serviceConfig = {
            Type = "exec";
            # Reset oo7's upstream ImportCredential entry before defining the
            # same credential name via LoadCredential. systemd otherwise
            # rejects the duplicate destination with EEXIST.
            ImportCredential = "";
            LoadCredential = "oo7.keyring-encryption-password:${credentialSocket}";
          };
        };

        systemd.user.services.oo7-unlock-check = {
          description = "Verify the DPAPI-bound oo7 Login keyring is unlocked";
          bindsTo = [ "oo7-daemon.service" ];
          after = [ "oo7-daemon.service" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${lib.getExe' bridge "oo7-unlock-check"}";
            RemainAfterExit = true;
            PrivateNetwork = true;
            PrivateUsers = true;
            PrivateTmp = true;
            PrivateDevices = true;
            NoNewPrivileges = true;
            SupplementaryGroups = "";
            ProtectSystem = "full";
            ProtectKernelTunables = true;
            ProtectKernelModules = true;
            ProtectControlGroups = true;
            MemoryDenyWriteExecute = true;
            ProtectClock = true;
            TimeoutStartSec = "10s";
          };
        };
      };
  };
}
