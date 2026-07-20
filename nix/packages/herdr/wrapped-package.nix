{
  herdr,
  writeShellApplication,
}:
writeShellApplication {
  name = "herdr";
  text = ''
    export HERDR_BIN=${herdr}/bin/herdr
    ${builtins.readFile ./herdr-wrapper.sh}
  '';
}
