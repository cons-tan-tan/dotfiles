{
  lib,
  rustPlatform,
}:

rustPlatform.buildRustPackage {
  pname = "apply-secrets";
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

  meta = {
    description = "Decrypt and atomically install manifest-managed secrets";
    license = lib.licenses.cc0;
    mainProgram = "apply-secrets";
  };
}
