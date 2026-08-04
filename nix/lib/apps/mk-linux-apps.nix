{
  homedir,
  inputs,
  username,
  windowsHomedir,
}:
{
  system,
  pkgs,
  homeTargets,
  nixosTarget,
  nixosRebuildBin,
}:
let
  inherit (pkgs.lib) escapeShellArg;
  appSet = import ./mk-app-set.nix { lib = pkgs.lib; };

  inherit (homeTargets) linux wsl;
  hmBin = "${inputs.home-manager.packages.${system}.default}/bin/home-manager";
  nhCleanupSystemd = pkgs.callPackage ../../packages/nh-cleanup-systemd {
    inherit homedir username;
    nh = pkgs.nh;
    nix = pkgs.nix;
  };

  buildScript = pkgs.writeShellApplication {
    name = "linux-host-build";
    text = ''
      export HM_TARGET_WSL=${escapeShellArg wsl}
      export HM_TARGET_LINUX=${escapeShellArg linux}
      export NIXOS_TARGET=${escapeShellArg nixosTarget}
      ${builtins.readFile ../../apps/linux-host-build.sh}
    '';
  };

  switchScript = pkgs.writeShellApplication {
    name = "linux-host-switch";
    text = ''
      export HM_TARGET_WSL=${escapeShellArg wsl}
      export HM_TARGET_LINUX=${escapeShellArg linux}
      export HM_BIN=${escapeShellArg hmBin}
      export NIXOS_TARGET=${escapeShellArg nixosTarget}
      export NIXOS_REBUILD_BIN=${escapeShellArg nixosRebuildBin}
      export NH_CLEANUP_SYSTEMD_INSTALLER=${escapeShellArg "${nhCleanupSystemd}/bin/install-nh-cleanup-systemd"}
      ${builtins.readFile ../../apps/linux-host-switch.sh}
    '';
  };

  applyWingetScript = pkgs.writeShellApplication {
    name = "apply-winget";
    text = ''
      export APPLY_WINGET_WINDOWS_HOMEDIR=${escapeShellArg windowsHomedir}
      ${builtins.readFile ../../apps/apply-winget.sh}
    '';
  };
in
appSet.mkAppSet {
  entries = {
    build = {
      description = "Build the host configuration without activating it (auto-detects NixOS-WSL/Home Manager)";
      script = buildScript;
    };
    switch = {
      description = "Build and activate the host configuration (auto-detects NixOS-WSL/Home Manager)";
      script = switchScript;
    };
    apply-winget = {
      description = "Apply the WinGet DSC configuration on the Windows host (WSL only)";
      script = applyWingetScript;
    };
  };
}
