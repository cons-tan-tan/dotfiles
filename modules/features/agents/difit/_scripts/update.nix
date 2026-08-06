{
  gitMinimal,
  jq,
  nix,
  nix-update,
  perl,
  ripgrep,
  writeShellApplication,
}:
writeShellApplication {
  name = "update-difit";
  runtimeInputs = [
    gitMinimal
    jq
    nix
    nix-update
    perl
    ripgrep
  ];
  text = builtins.readFile ./update.sh;
}
