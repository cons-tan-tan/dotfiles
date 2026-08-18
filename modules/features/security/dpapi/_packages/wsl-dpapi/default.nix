{
  lib,
  pkgsCross,
  rustPlatform,
}:
let
  source = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./Cargo.toml
      ./Cargo.lock
      ./src
    ];
  };
  common = {
    pname = "wsl-dpapi";
    version = "0.1.0";
    src = source;
    cargoLock.lockFile = ./Cargo.lock;
  };
  nativeTests = rustPlatform.buildRustPackage (
    common
    // {
      pname = "wsl-dpapi-native-tests";
      cargoTestFlags = [ "--all-targets" ];
      meta = {
        description = "Native unit tests for the WSL DPAPI envelope";
        license = lib.licenses.cc0;
        platforms = lib.platforms.linux;
      };
    }
  );
in
# Windows 11 on Arm transparently emulates user-mode x64 applications. Using
# pkgsCross.ucrt64 keeps one mature Windows target for both WSL architectures.
pkgsCross.ucrt64.rustPlatform.buildRustPackage (
  common
  // {
    doCheck = false;
    passthru.tests = nativeTests;
    meta = {
      description = "Binary stdin/stdout bridge for Windows CurrentUser DPAPI from WSL";
      license = lib.licenses.cc0;
      mainProgram = "wsl-dpapi.exe";
      platforms = lib.platforms.windows;
    };
  }
)
