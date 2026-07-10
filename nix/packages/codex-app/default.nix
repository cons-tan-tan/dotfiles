{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "codex-app";
  version = "26.707.31428";

  src = fetchurl {
    url = "https://persistent.oaistatic.com/codex-app-prod/ChatGPT-darwin-arm64-${finalAttrs.version}.zip";
    hash = "sha256-/9w1GlBxBdVddGTjNAMCx1i4pUuSZxHEsVvzc8y0fWQ=";
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
    cp -R ChatGPT.app "$out/Applications/"
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
})
