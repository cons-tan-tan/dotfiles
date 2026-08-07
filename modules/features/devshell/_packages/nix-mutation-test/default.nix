{
  bash,
  lib,
  makeWrapper,
  nix,
  rsync,
  rustPlatform,
}:
rustPlatform.buildRustPackage {
  pname = "nix-mutation-test";
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
  cargoTestFlags = [
    "--all-targets"
    "--all-features"
  ];

  nativeBuildInputs = [ makeWrapper ];

  postInstall = ''
    wrapProgram "$out/bin/nix-mutation-test" \
      --prefix PATH : ${
        lib.makeBinPath [
          bash
          nix
          rsync
        ]
      }
  '';

  meta = {
    description = "Lossless AST-based mutation test runner for Nix expressions";
    license = lib.licenses.cc0;
    mainProgram = "nix-mutation-test";
  };
}
