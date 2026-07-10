{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
}:

let
  pin = lib.importJSON ../../pins/codex-app.json;
in
stdenvNoCC.mkDerivation {
  pname = "codex-app";
  version = pin.version;

  src = fetchurl {
    inherit (pin) url hash;
  };

  nativeBuildInputs = [ unzip ];

  sourceRoot = ".";

  unpackPhase = ''
    runHook preUnpack
    unzip -q "$src"
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/Applications"
    cp -R ${lib.escapeShellArg pin.appName} "$out/Applications/"
    runHook postInstall
  '';

  # Keep the upstream-signed application bundle byte-for-byte after extraction.
  dontFixup = true;

  meta = {
    description = "OpenAI Codex desktop app";
    homepage = "https://openai.com/codex";
    license = lib.licenses.unfree;
    platforms = [ "aarch64-darwin" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
