{
  gitMinimal,
  jq,
  nix,
  nodejs_24,
  perl,
  ripgrep,
  writeShellApplication,
}:
writeShellApplication {
  name = "update-bee";
  runtimeInputs = [
    gitMinimal
    jq
    nix
    nodejs_24
    perl
    ripgrep
  ];
  text = builtins.readFile ./update.sh;
}
