{
  lib,
  stdenvNoCC,
  fetchurl,
  hcomSource,
  hcomPin ? builtins.fromJSON (builtins.readFile ../../pins/hcom.json),
}:
let
  # version は skill と共有する hcom-src、配布物の hash は JSON pin が所有する。
  # `nix run .#update-pins` は両方を同じ transaction で更新する。
  # Linux uses the static musl build: no glibc dependency, so autoPatchelfHook
  # is unnecessary. macOS has no musl variant, so use the native darwin build.
  version = (builtins.fromTOML (builtins.readFile "${hcomSource}/Cargo.toml")).package.version;

  system = stdenvNoCC.hostPlatform.system;
  pinnedAsset = import ../../lib/mk-pinned-asset.nix {
    pin = hcomPin;
    inherit system;
    label = "hcom";
  };
  asset = pinnedAsset.asset;
in
stdenvNoCC.mkDerivation {
  pname = "hcom";
  inherit version;

  src = fetchurl {
    url = "https://github.com/aannoo/hcom/releases/download/v${version}/${asset.name}";
    inherit (asset) hash;
  };

  # Don't hardcode the inner target-named dir; locate the binary instead so a
  # tarball layout change doesn't silently break the build.
  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    bin="$(find . -type f -name hcom | head -1)"
    if [ -z "$bin" ]; then
      echo "hcom: binary not found in release tarball" >&2
      exit 1
    fi
    install -Dm755 "$bin" "$out/bin/hcom"
    runHook postInstall
  '';

  meta = with lib; {
    description = "Let AI agents message, watch, and spawn each other across terminals";
    homepage = "https://github.com/aannoo/hcom";
    license = licenses.mit;
    platforms = pinnedAsset.platforms;
    mainProgram = "hcom";
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
  };
}
