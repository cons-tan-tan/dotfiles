{
  lib,
  rustPlatform,
}:
rustPlatform.buildRustPackage {
  pname = "apply-nix-settings";
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
    description = "Atomically apply repository-managed Nix daemon settings";
    license = lib.licenses.cc0;
    mainProgram = "apply-nix-settings";
  };
}
