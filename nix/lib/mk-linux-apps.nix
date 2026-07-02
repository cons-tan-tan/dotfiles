{
  inputs,
  username,
  windowsUsername,
  windowsHomedir,
  linuxShortArch,
}:
system: pkgs:
let
  arch = linuxShortArch.${system};
  hmBin = "${inputs.home-manager.packages.${system}.default}/bin/home-manager";

  buildScript = pkgs.writeShellApplication {
    name = "home-manager-build";
    text = ''
      export HM_USERNAME=${username}
      export HM_ARCH=${arch}
      ${builtins.readFile ../apps/home-manager-build.sh}
    '';
  };

  switchScript = pkgs.writeShellApplication {
    name = "home-manager-switch";
    text = ''
      export HM_USERNAME=${username}
      export HM_ARCH=${arch}
      export HM_BIN=${hmBin}
      ${builtins.readFile ../apps/home-manager-switch.sh}
    '';
  };

  applyWingetScript = pkgs.writeShellApplication {
    name = "apply-winget";
    text = ''
      export APPLY_WINGET_WINDOWS_HOMEDIR=${windowsHomedir}
      export APPLY_WINGET_WINDOWS_USERNAME=${windowsUsername}
      ${builtins.readFile ../apps/apply-winget.sh}
    '';
  };
in
{
  apps = {
    build = {
      type = "app";
      meta.description = "Build the Home Manager configuration without activating it (auto-detects WSL/Linux)";
      program = pkgs.lib.getExe buildScript;
    };
    switch = {
      type = "app";
      meta.description = "Build and activate the Home Manager configuration (auto-detects WSL/Linux)";
      program = pkgs.lib.getExe switchScript;
    };
    apply-winget = {
      type = "app";
      meta.description = "Apply the WinGet DSC configuration on the Windows host (WSL only)";
      program = pkgs.lib.getExe applyWingetScript;
    };
  };

  scripts = [
    buildScript
    switchScript
    applyWingetScript
  ];
}
