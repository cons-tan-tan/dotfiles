{
  lib,
  rustPlatform,
}:
rustPlatform.buildRustPackage {
  pname = "codex-config-helper";
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
  cargoTestFlags = [ "--all-features" ];

  meta = {
    description = "Internal helper for merging Codex config and generating hook trust state";
    license = lib.licenses.cc0;
    mainProgram = "codex-config-helper";
  };
}
