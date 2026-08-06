{
  callPackage,
  ghApiGet,
  lib,
  stdenvNoCC,
  fetchurl,
  makeBinaryWrapper,
  chromium,
  agentBrowserSource,
  mkPinnedAsset,
  pin ? builtins.fromJSON (builtins.readFile ./pin.json),
}:
let
  updater = callPackage ../../_scripts/update.nix { inherit ghApiGet; };
  version = (builtins.fromJSON (builtins.readFile "${agentBrowserSource}/package.json")).version;
  system = stdenvNoCC.hostPlatform.system;
  pinnedAsset = mkPinnedAsset {
    inherit pin system;
    label = "agent-browser";
  };
  asset = pinnedAsset.asset;
in
stdenvNoCC.mkDerivation {
  pname = "agent-browser";
  inherit version;

  src = fetchurl {
    url = "https://github.com/vercel-labs/agent-browser/releases/download/v${version}/${asset.name}";
    inherit (asset) hash;
  };

  dontUnpack = true;

  nativeBuildInputs = lib.optionals stdenvNoCC.hostPlatform.isLinux [
    makeBinaryWrapper
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/agent-browser"
    cp -r ${agentBrowserSource}/skills ${agentBrowserSource}/skill-data "$out/"
    runHook postInstall
  '';

  postFixup = lib.optionalString stdenvNoCC.hostPlatform.isLinux ''
    wrapProgram "$out/bin/agent-browser" \
      --set AGENT_BROWSER_EXECUTABLE_PATH "${chromium}/bin/chromium"
  '';

  passthru = {
    updateScript = lib.getExe updater;
    updateScriptName = "agent-browser";
    updateScriptDescription = "Update agent-browser release input and native assets";
  };

  meta = {
    description = "Headless browser automation CLI for AI agents";
    homepage = "https://github.com/vercel-labs/agent-browser";
    changelog = "https://github.com/vercel-labs/agent-browser/releases/tag/v${version}";
    license = lib.licenses.asl20;
    platforms = pinnedAsset.platforms;
    mainProgram = "agent-browser";
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
