{
  coreutils,
  herdr,
  lib,
  sleepBin ? lib.getExe' coreutils "sleep",
  writeShellApplication,
}:
writeShellApplication {
  name = "herdr";
  text = ''
    export HERDR_BIN=${herdr}/bin/herdr
    export HERDR_SLEEP_BIN=${sleepBin}
    ${builtins.readFile ./herdr-wrapper.sh}
  '';
}
