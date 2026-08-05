{
  curl,
  lib,
  makeWrapper,
  runCommand,
  rustPlatform,
}:
let
  core = rustPlatform.buildRustPackage {
    pname = "safe-fetch-core";
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
      description = "Typed argument policies for read-only curl and GitHub API wrappers";
      license = lib.licenses.cc0;
    };
  };

  curlFetch =
    runCommand "curl-fetch"
      {
        nativeBuildInputs = [ makeWrapper ];
        meta = {
          description = "Fetch HTTP(S) resources through a read-only curl policy";
          license = lib.licenses.cc0;
          mainProgram = "curl-fetch";
        };
      }
      ''
        mkdir -p "$out/bin"
        makeWrapper "${core}/bin/curl-fetch" "$out/bin/curl-fetch" \
          --set SAFE_FETCH_CURL_BIN "${lib.getExe curl}" \
          --unset QLOGDIR \
          --unset SSLKEYLOGFILE
      '';
in
{
  inherit core curlFetch;
}
