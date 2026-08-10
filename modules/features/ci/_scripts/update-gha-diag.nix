{
  coreutils,
  gitMinimal,
  gnugrep,
  gnutar,
  gzip,
  jq,
  nix,
  nodejs_24,
  openssl,
  pnpm_11,
  writeShellApplication,
}:
writeShellApplication {
  name = "update-gha-diag";
  runtimeInputs = [
    coreutils
    gitMinimal
    gnugrep
    gnutar
    gzip
    jq
    nix
    nodejs_24
    openssl
    pnpm_11
  ];
  runtimeEnv.GHA_DIAG_EXPERIMENTAL_FEATURE_EXTRACTOR = ./extract-gha-diag-experimental-features.mjs;
  text = builtins.readFile ./update-gha-diag.sh;
}
