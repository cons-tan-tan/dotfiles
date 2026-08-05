{
  lib,
  rustPlatform,
}:
rustPlatform.buildRustPackage {
  pname = "agent-command-guard";
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
  cargoTestFlags = [ "--all-targets" ];

  meta = {
    description = "Shared semantic command guard for coding agent hooks";
    license = lib.licenses.cc0;
    mainProgram = "agent-command-guard";
  };
}
