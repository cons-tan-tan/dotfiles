{
  coreutils,
  ghApiGet,
  gitMinimal,
  jq,
  nix,
  writeShellApplication,
}:
writeShellApplication {
  name = "update-herdr";
  runtimeInputs = [
    coreutils
    ghApiGet
    gitMinimal
    jq
    nix
  ];
  text = builtins.readFile ./update.sh;
}
