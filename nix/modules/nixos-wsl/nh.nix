{
  config,
  lib,
  ...
}:
let
  cleanupPolicy = import ../../lib/nh-clean-policy.nix;
in
{
  # The system generation is root-owned, so NixOS must own automatic cleanup.
  # Interactive nh remains Home Manager-managed; the NixOS module deliberately
  # supports enabling only its privileged `nh clean all` service.
  programs.nh.clean = {
    enable = true;
    dates = cleanupPolicy.dates;
    extraArgs = lib.escapeShellArgs cleanupPolicy.arguments;
  };

  systemd.services.nh-clean.serviceConfig = {
    User = "root";
    Nice = 10;
    IOSchedulingClass = "idle";
  };

  assertions = [
    {
      assertion = !config.nix.gc.automatic;
      message = "programs.nh.clean and nix.gc.automatic must not run together";
    }
  ];
}
