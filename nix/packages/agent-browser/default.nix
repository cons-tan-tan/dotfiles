{
  lib,
  stdenvNoCC,
  fetchurl,
  fetchFromGitHub,
  makeBinaryWrapper,
  chromium,
  pin ? builtins.fromJSON (builtins.readFile ../../pins/agent-browser.json),
}:
let
  inherit (pin) version;
  system = stdenvNoCC.hostPlatform.system;
  asset = pin.assets.${system} or (throw "agent-browser: unsupported system '${system}'");
  source = fetchFromGitHub {
    owner = "vercel-labs";
    repo = "agent-browser";
    # Upstream has a branch and a tag both named v<version>; pin the tag ref.
    tag = "v${version}";
    hash = pin.srcHash;
  };
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
    cp -r ${source}/skills ${source}/skill-data "$out/"
    runHook postInstall
  '';

  postFixup = lib.optionalString stdenvNoCC.hostPlatform.isLinux ''
    wrapProgram "$out/bin/agent-browser" \
      --set AGENT_BROWSER_EXECUTABLE_PATH "${chromium}/bin/chromium"
  '';

  meta = {
    description = "Headless browser automation CLI for AI agents";
    homepage = "https://github.com/vercel-labs/agent-browser";
    changelog = "https://github.com/vercel-labs/agent-browser/releases/tag/v${version}";
    license = lib.licenses.asl20;
    platforms = builtins.attrNames pin.assets;
    mainProgram = "agent-browser";
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
