{ lib }:
{
  describe =
    target:
    let
      inherit (target) config pkgs;
      configText = lib.attrByPath [ "xdg" "configFile" "sshenc/config.toml" "text" ] null config;
      package = lib.findFirst (candidate: lib.getName candidate == "sshenc") null config.home.packages;
      service = lib.attrByPath [ "systemd" "user" "services" "sshenc-agent" ] null config;
      serviceConfig = if service == null then { } else service.Service;
    in
    {
      packageInstalled = package != null;
      inherit configText;
      allowedSigners = lib.attrByPath [
        "programs"
        "git"
        "settings"
        "gpg"
        "ssh"
        "allowedSignersFile"
      ] null config;
      service =
        if service == null then
          null
        else
          {
            wantedBy = service.Install.WantedBy;
            inherit (serviceConfig)
              KillSignal
              NoNewPrivileges
              PrivateTmp
              ProtectSystem
              Restart
              UMask
              ;
            foregroundAgent =
              package != null
              && lib.toList serviceConfig.ExecStart == [ "${package}/bin/sshenc-agent --foreground" ];
            metadataDirectory = builtins.elem "${pkgs.coreutils}/bin/mkdir -p %h/.sshenc/keys" (
              lib.toList (serviceConfig.ExecStartPre or [ ])
            );
            tpmBridge =
              package != null
              && builtins.elem "SSHENC_BRIDGE_PATH=${package}/bin/sshenc-tpm-bridge.exe" (
                lib.toList (serviceConfig.Environment or [ ])
              );
          };
    };

  expected =
    facts:
    if facts.environment == "wsl" && !facts.standalone then
      {
        packageInstalled = true;
        configText = ''
          allowed_labels = ["git-signing"]
        '';
        allowedSigners = "~/.ssh/allowed_signers";
        service = {
          wantedBy = [ "default.target" ];
          KillSignal = "SIGINT";
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "full";
          Restart = "on-failure";
          UMask = "0077";
          foregroundAgent = true;
          metadataDirectory = true;
          tpmBridge = true;
        };
      }
    else
      {
        packageInstalled = false;
        configText = null;
        allowedSigners = null;
        service = null;
      };
}
