{
  lib,
}:
{
  describe =
    target:
    let
      config = target.config;
      pinentry = config.services.gpg-agent.pinentry.package;
      systemdServices = lib.attrByPath [ "systemd" "user" "services" ] { } config;
    in
    {
      programs = {
        gpg = config.programs.gpg.enable;
        gpgAgentZsh = config.services.gpg-agent.enableZshIntegration;
      };
      cacheTtl = config.services.gpg-agent.defaultCacheTtl;
      maxCacheTtl = config.services.gpg-agent.maxCacheTtl;
      sshSupport = config.services.gpg-agent.enableSshSupport;
      sshKeys = config.services.gpg-agent.sshKeys;
      windowsPinentry = lib.hasInfix "Gpg4win/bin/pinentry.exe" config.services.gpg-agent.extraConfig;
      pinentry = if pinentry == null then null else lib.getName pinentry;
      wslAuthSockOverride = lib.any (
        command: lib.hasInfix "set-SSH_AUTH_SOCK-wsl" command
      ) systemdServices.set-SSH_AUTH_SOCK.Service.ExecStart;
    };
  expected = facts: {
    programs = {
      gpg = true;
      gpgAgentZsh = true;
    };
    cacheTtl = 43200;
    maxCacheTtl = 43200;
    sshSupport = true;
    sshKeys = [ "60DE257CE1919B3D6DCF4E6E239CD1FFE63B45FD" ];
    windowsPinentry = facts.environment == "wsl";
    pinentry =
      {
        darwin = "pinentry-mac";
        linux = "pinentry-curses";
        wsl = null;
      }
      .${facts.environment};
    wslAuthSockOverride = facts.environment == "wsl";
  };
}
