{
  cargo,
  coreutils,
  gitMinimal,
  ghApiGet,
  jq,
  nix,
  nix-update,
  patch,
  perl,
  ripgrep,
  rustc,
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
    patch
    perl
    ripgrep
    rustc
  ];
  text = builtins.readFile ./update-shellfirm.sh;
}
