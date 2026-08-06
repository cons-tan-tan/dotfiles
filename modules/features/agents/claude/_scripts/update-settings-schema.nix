{
  coreutils,
  gitMinimal,
  jq,
  nix,
  writeShellApplication,
}:
writeShellApplication {
  name = "update-claude-settings-schema";
  runtimeInputs = [
    coreutils
    gitMinimal
    jq
    nix
  ];
  text = builtins.readFile ./update-settings-schema.sh;
}
