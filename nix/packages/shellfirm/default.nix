{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  openssl,
  pin ? builtins.fromJSON (builtins.readFile ../../pins/shellfirm.json),
}:

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

  cargoBuildFlags = [
    "--package"
    pname
  ];
  cargoTestFlags = cargoBuildFlags;

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ openssl ];

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
