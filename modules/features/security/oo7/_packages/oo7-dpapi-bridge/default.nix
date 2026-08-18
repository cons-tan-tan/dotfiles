{
  lib,
  rustPlatform,
}:
rustPlatform.buildRustPackage {
  pname = "oo7-dpapi-bridge";
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
    description = "Safe bootstrap and unlock verification for oo7 with WSL DPAPI";
    license = lib.licenses.cc0;
    mainProgram = "oo7-dpapi-bridge";
    platforms = lib.platforms.linux;
  };
}
