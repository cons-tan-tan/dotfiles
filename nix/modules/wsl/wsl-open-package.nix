{
  coreutils,
  lib,
  realpathBin ? lib.getExe' coreutils "realpath",
  rundll32Bin ? "/mnt/c/Windows/System32/rundll32.exe",
  symlinkJoin,
  writeShellApplication,
  wslpathBin ? "wslpath",
}:
let
  wsl-open-bin = writeShellApplication {
    name = "wsl-open";
    runtimeInputs = [ coreutils ];
    text = ''
      export WSL_OPEN_REALPATH_BIN=${lib.escapeShellArg realpathBin}
      export WSL_OPEN_WSLPATH_BIN=${lib.escapeShellArg wslpathBin}
      export WSL_OPEN_HANDLER_BIN=${lib.escapeShellArg rundll32Bin}
      ${builtins.readFile ./wsl-open.sh}
    '';
  };
in
symlinkJoin {
  name = "wsl-open";
  paths = [ wsl-open-bin ];
  postBuild = ''
    ln -s wsl-open "$out/bin/x-www-browser"
  '';
}
