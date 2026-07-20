{
  lib,
  packageDir,
  pi,
  writeShellApplication,
}:
writeShellApplication {
  name = "pi";
  text = ''
    PI_BIN=${lib.escapeShellArg "${pi}/bin/pi"}
    PI_MANAGED_PACKAGE_DIR=${lib.escapeShellArg packageDir}
    ${builtins.readFile ./pi-wrapper.sh}
  '';
}
