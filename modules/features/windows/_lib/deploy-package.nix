{
  pkgs,
  mvBin ? pkgs.lib.getExe' pkgs.coreutils "mv",
  rootPrefix ? "/mnt/c/Users",
  rsyncBin ? pkgs.lib.getExe pkgs.rsync,
}:
pkgs.writeShellApplication {
  name = "windows-companion-deploy";
  runtimeInputs = [
    pkgs.coreutils
    pkgs.jq
    pkgs.rsync
  ];
  text = ''
    WINDOWS_COMPANION_DEPLOY_ROOT_PREFIX=${pkgs.lib.escapeShellArg rootPrefix}
    WINDOWS_COMPANION_DEPLOY_MV_BIN=${pkgs.lib.escapeShellArg mvBin}
    WINDOWS_COMPANION_DEPLOY_RSYNC_BIN=${pkgs.lib.escapeShellArg rsyncBin}
    ${builtins.readFile ./deploy.sh}
  '';
}
