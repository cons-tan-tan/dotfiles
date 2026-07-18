{ config, ... }:
{
  programs.nh = {
    enable = true;

    clean = {
      # Home Manager currently appends extraArgs as one launchd argument.
      # Keep automatic cleanup on the systemd-backed hosts where it is split correctly.
      enable = config.my.isLinux || config.my.isWsl;
      dates = "weekly";
      extraArgs = "--keep-since 30d --keep-one";
    };
  };
}
