{
  lib,
  rustPlatform,
}:
rustPlatform.buildRustPackage {
  pname = "aws-config-helper";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./Cargo.toml
      ./Cargo.lock
      ./src
      ./tests
    ];
  };

  cargoLock.lockFile = ./Cargo.lock;
  cargoTestFlags = [
    "--all-targets"
    "--all-features"
  ];

  meta = {
    description = "Transactional AWS config mutation helper";
    license = lib.licenses.cc0;
    mainProgram = "aws-config-helper";
  };
}
