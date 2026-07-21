{
  inputs,
  username,
  windowsUsername,
  windowsHomedir,
}:
{ system, pkgs }:
let
  inherit (pkgs.lib) escapeShellArg;
  appSet = import ./mk-app-set.nix { lib = pkgs.lib; };

  configNames = import ./linux-config-name.nix { inherit username; };
  wslTarget = configNames.forHost {
    hostKind = "wsl";
    inherit system;
  };
  linuxTarget = configNames.forHost {
    hostKind = "linux";
    inherit system;
  };
  hmBin = "${inputs.home-manager.packages.${system}.default}/bin/home-manager";

  buildScript = pkgs.writeShellApplication {
    name = "home-manager-build";
    text = ''
      export HM_TARGET_WSL=${escapeShellArg wslTarget}
      export HM_TARGET_LINUX=${escapeShellArg linuxTarget}
      ${builtins.readFile ../apps/home-manager-build.sh}
    '';
  };

  switchScript = pkgs.writeShellApplication {
    name = "home-manager-switch";
    text = ''
      export HM_TARGET_WSL=${escapeShellArg wslTarget}
      export HM_TARGET_LINUX=${escapeShellArg linuxTarget}
      export HM_BIN=${escapeShellArg hmBin}
      ${builtins.readFile ../apps/home-manager-switch.sh}
    '';
  };

  applyWingetScript = pkgs.writeShellApplication {
    name = "apply-winget";
    text = ''
      export APPLY_WINGET_WINDOWS_HOMEDIR=${escapeShellArg windowsHomedir}
      export APPLY_WINGET_WINDOWS_USERNAME=${escapeShellArg windowsUsername}
      ${builtins.readFile ../apps/apply-winget.sh}
    '';
  };
in
appSet.mkAppSet {
  entries = {
    build = {
      description = "Build the Home Manager configuration without activating it (auto-detects WSL/Linux)";
      script = buildScript;
    };
    switch = {
      description = "Build and activate the Home Manager configuration (auto-detects WSL/Linux)";
      script = switchScript;
    };
    apply-winget = {
      description = "Apply the WinGet DSC configuration on the Windows host (WSL only)";
      script = applyWingetScript;
    };
  };
}
