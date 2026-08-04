{
  curl,
  git,
  lib,
  makeWrapper,
  nix,
  rustPlatform,
  smoke ? false,
}:

rustPlatform.buildRustPackage {
  pname = if smoke then "update-pins-smoke" else "update-pins";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./Cargo.toml
      ./Cargo.lock
      ./src
    ];
  };

  cargoLock.lockFile = ./Cargo.lock;

  cargoBuildFlags =
    if smoke then
      [
        "--no-default-features"
        "--features"
        "smoke"
        "--bin"
        "update-pins-smoke"
      ]
    else
      [
        "--bin"
        "update-pins"
      ];

  # The normal package still compiles and tests the read-only module, while
  # installing only the public updater binary selected above.
  cargoTestFlags =
    if smoke then
      [
        "--no-default-features"
        "--features"
        "smoke"
      ]
    else
      [
        "--features"
        "smoke"
      ];

  nativeBuildInputs = lib.optionals smoke [ makeWrapper ];
  nativeCheckInputs = [ git ];

  postFixup = lib.optionalString smoke ''
    wrapProgram "$out/bin/update-pins-smoke" \
      --set PATH ${
        lib.makeBinPath [
          curl
          nix
        ]
      }
  '';

  meta = {
    description =
      if smoke then
        "Check update-pins assumptions against live upstream metadata"
      else
        "Synchronize repository pins with their upstream releases";
    license = lib.licenses.cc0;
    mainProgram = if smoke then "update-pins-smoke" else "update-pins";
  };
}
