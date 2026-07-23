{
  git,
  lib,
  rustPlatform,
}:

rustPlatform.buildRustPackage {
  pname = "update-pins";
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

  nativeCheckInputs = [ git ];

  meta = {
    description = "Synchronize repository pins with their upstream releases";
    license = lib.licenses.cc0;
    mainProgram = "update-pins";
  };
}
