{
  coreutils,
  gitMinimal,
  jq,
  libplist,
  nix,
  unzip,
  writeShellApplication,
  xmlstarlet,
}:
writeShellApplication {
  name = "update-codex-app";
  runtimeInputs = [
    coreutils
    gitMinimal
    jq
    libplist
    nix
    unzip
    xmlstarlet
  ];
  text = builtins.readFile ./update-app.sh;
}
