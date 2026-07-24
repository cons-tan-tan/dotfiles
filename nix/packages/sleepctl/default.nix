{
  lib,
  rustPlatform,
}:

rustPlatform.buildRustPackage {
  pname = "sleepctl";
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

  cargoBuildFlags = [
    "--bin"
    "sleepctl"
    "--bin"
    "sleepctld"
  ];

  cargoTestFlags = [ "--all-targets" ];

  meta = {
    description = "Run deadline-bound macOS sleep leases with thermal safeguards";
    license = lib.licenses.cc0;
    mainProgram = "sleepctl";
    platforms = lib.platforms.darwin;
  };
}
