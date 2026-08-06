{
  coreutils,
  ghApiGet,
  gitMinimal,
  jq,
  nix,
  perl,
  ripgrep,
  writeShellApplication,
}:
writeShellApplication {
  name = "update-hcom";
  runtimeInputs = [
    coreutils
    ghApiGet
    gitMinimal
    jq
    nix
    perl
    ripgrep
  ];
  text = builtins.readFile ./update.sh;
}
