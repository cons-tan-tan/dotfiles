{
  cargo,
  coreutils,
  gitMinimal,
  ghApiGet,
  jq,
  nix,
  nix-update,
  perl,
  ripgrep,
  writeShellApplication,
}:
writeShellApplication {
  name = "update-shellfirm";
  runtimeInputs = [
    cargo
    coreutils
    gitMinimal
    ghApiGet
    jq
    nix
    nix-update
    perl
    ripgrep
  ];
  text = builtins.readFile ./update-shellfirm.sh;
}
