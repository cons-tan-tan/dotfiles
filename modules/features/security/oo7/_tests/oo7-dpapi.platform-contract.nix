{
  integratedWslSystem,
  lib,
  standaloneWsl,
}:
let
  prepare = integratedWslSystem.systemd.user.services.oo7-dpapi-prepare;
  provider = integratedWslSystem.systemd.user.services."oo7-dpapi-credential@";
  socket = integratedWslSystem.systemd.user.sockets.oo7-dpapi-credential;
  daemon = integratedWslSystem.systemd.user.services.oo7-daemon;
  unlockCheck = integratedWslSystem.systemd.user.services.oo7-unlock-check;
  standaloneServices = standaloneWsl.systemd.user.services;
  standaloneSockets = standaloneWsl.systemd.user.sockets;
in
{
  actual = {
    integrated = {
      oo7 = integratedWslSystem.services.oo7.enable;
      pamLoginUnlock = integratedWslSystem.security.pam.services.login.oo7.enable;
      prepare = {
        inherit (prepare) before;
        inherit (prepare.serviceConfig)
          NoNewPrivileges
          RemainAfterExit
          TimeoutStartSec
          Type
          UMask
          ;
        execProtocol =
          lib.hasInfix "/bin/oo7-dpapi-bridge /nix/store/" prepare.serviceConfig.ExecStart
          && lib.hasSuffix "/bin/wsl-dpapi.exe %S/oo7-dpapi/login-master.dpapi" prepare.serviceConfig.ExecStart;
      };
      provider = {
        inherit (provider.unitConfig) CollectMode;
        inherit (provider.serviceConfig)
          NoNewPrivileges
          StandardInput
          StandardOutput
          TimeoutStartSec
          Type
          UMask
          ;
        execProtocol = lib.hasSuffix "/bin/wsl-dpapi.exe unprotect" provider.serviceConfig.ExecStart;
      };
      socket = {
        inherit (socket) wantedBy;
        inherit (socket.socketConfig)
          Accept
          ListenStream
          RemoveOnStop
          SocketMode
          ;
        serviceOverride = socket.socketConfig.Service or null;
      };
      daemon = {
        inherit (daemon)
          after
          bindsTo
          requires
          wantedBy
          ;
        inherit (daemon.serviceConfig) ImportCredential LoadCredential Type;
        execStartPost = daemon.serviceConfig.ExecStartPost or null;
      };
      unlockCheck = {
        inherit (unlockCheck) after bindsTo;
        inherit (unlockCheck.serviceConfig)
          NoNewPrivileges
          MemoryDenyWriteExecute
          PrivateDevices
          PrivateNetwork
          PrivateTmp
          PrivateUsers
          ProtectClock
          ProtectControlGroups
          ProtectKernelModules
          ProtectKernelTunables
          ProtectSystem
          RemainAfterExit
          SupplementaryGroups
          TimeoutStartSec
          Type
          ;
        execProtocol = lib.hasSuffix "/bin/oo7-unlock-check" unlockCheck.serviceConfig.ExecStart;
      };
    };
    standalone = {
      prepare = builtins.hasAttr "oo7-dpapi-prepare" standaloneServices;
      provider = builtins.hasAttr "oo7-dpapi-credential@" standaloneServices;
      socket = builtins.hasAttr "oo7-dpapi-credential" standaloneSockets;
      unlockCheck = builtins.hasAttr "oo7-unlock-check" standaloneServices;
    };
  };
  expected = {
    integrated = {
      oo7 = true;
      pamLoginUnlock = false;
      prepare = {
        before = [ "oo7-daemon.service" ];
        NoNewPrivileges = true;
        RemainAfterExit = false;
        TimeoutStartSec = "30s";
        Type = "oneshot";
        UMask = "0077";
        execProtocol = true;
      };
      provider = {
        CollectMode = "inactive-or-failed";
        NoNewPrivileges = true;
        StandardInput = "file:%S/oo7-dpapi/login-master.dpapi";
        StandardOutput = "socket";
        TimeoutStartSec = "10s";
        Type = "oneshot";
        UMask = "0077";
        execProtocol = true;
      };
      socket = {
        wantedBy = [ "sockets.target" ];
        Accept = true;
        ListenStream = "%t/oo7-dpapi-credential.sock";
        RemoveOnStop = true;
        SocketMode = "0600";
        serviceOverride = null;
      };
      daemon = {
        after = [
          "oo7-dpapi-credential.socket"
          "oo7-dpapi-prepare.service"
        ];
        requires = [
          "oo7-dpapi-credential.socket"
          "oo7-dpapi-prepare.service"
        ];
        bindsTo = [ "oo7-unlock-check.service" ];
        wantedBy = [ "default.target" ];
        Type = "exec";
        ImportCredential = "";
        LoadCredential = "oo7.keyring-encryption-password:%t/oo7-dpapi-credential.sock";
        execStartPost = null;
      };
      unlockCheck = {
        after = [ "oo7-daemon.service" ];
        bindsTo = [ "oo7-daemon.service" ];
        NoNewPrivileges = true;
        MemoryDenyWriteExecute = true;
        PrivateDevices = true;
        PrivateNetwork = true;
        PrivateTmp = true;
        PrivateUsers = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectSystem = "full";
        RemainAfterExit = true;
        SupplementaryGroups = "";
        TimeoutStartSec = "10s";
        Type = "oneshot";
        execProtocol = true;
      };
    };
    standalone = {
      prepare = false;
      provider = false;
      socket = false;
      unlockCheck = false;
    };
  };
}
