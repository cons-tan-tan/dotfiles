{
  coreutils,
  jq,
  lib,
  nix,
  perl,
  writeShellApplication,
}:
writeShellApplication {
  name = "nix-store-growth-checker";
  runtimeInputs = [
    coreutils
    jq
    nix
    perl
  ];
  text = ''
    export NIX_STORE_GROWTH_JSON_FORMAT_1=${lib.boolToString (lib.versionAtLeast (lib.getVersion nix) "2.33")}
    ${builtins.readFile ./nix-store-growth-checker.sh}
  '';
}
