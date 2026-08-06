{
  callPackage,
  ghApiGet,
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  openssl,
  pin ? builtins.fromJSON (builtins.readFile ./pin.json),
}:
let
  updater = callPackage ../../_scripts/update-shellfirm.nix { inherit ghApiGet; };
in
rustPlatform.buildRustPackage rec {
  pname = "shellfirm";
  inherit (pin) version;

  src = fetchFromGitHub {
    owner = "kaplanelad";
    repo = "shellfirm";
    rev = "v${version}";
    hash = pin.srcHash;
  };

  cargoLock.lockFile = ./Cargo.lock;

  # Keep the release source while advancing vulnerable transitive dependencies
  # in the repository-owned lockfile. cargoSetup validates this copy against
  # the vendored dependency set before building.
  postPatch = ''
    cp ${./Cargo.lock} Cargo.lock
  '';

  cargoBuildFlags = [
    "--package"
    pname
  ];
  cargoTestFlags = cargoBuildFlags;

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ openssl ];

  passthru = {
    updateScript = lib.getExe updater;
    updateScriptName = "shellfirm";
    updateScriptDescription = "Update shellfirm with nix-update and synchronize Cargo locks";
  };

  meta = with lib; {
    description = "Safety guardrails for AI coding agents and human terminal commands";
    homepage = "https://github.com/kaplanelad/shellfirm";
    license = with licenses; [
      asl20
      mit
    ];
    mainProgram = "shellfirm";
  };
}
