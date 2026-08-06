{
  coreutils,
  ghApiGet,
  gitMinimal,
  jq,
  nix,
  writeShellApplication,
}:
writeShellApplication {
  name = "update-watchexec";
  runtimeInputs = [
    coreutils
    ghApiGet
    gitMinimal
    jq
    nix
  ];
  text = builtins.readFile ./update.sh;
}
