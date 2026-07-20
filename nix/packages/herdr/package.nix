{
  lib,
  stdenvNoCC,
  fetchurl,
  fetchFromGitHub,
  herdrPin ? builtins.fromJSON (builtins.readFile ../../pins/herdr.json),
}:
let
  system = stdenvNoCC.hostPlatform.system;
  inherit (herdrPin) version;
  asset = herdrPin.assets.${system} or (throw "herdr: unsupported system '${system}'");
  platforms = builtins.attrNames herdrPin.assets;
  src = fetchFromGitHub {
    owner = "ogulcancelik";
    repo = "herdr";
    rev = "v${version}";
    hash = herdrPin.srcHash;
  };
in
{
  inherit platforms src version;

  # Use upstream release binaries on every supported platform so evaluation does
  # not need to import generated files from a fetched source derivation.
  package = stdenvNoCC.mkDerivation {
    pname = "herdr";
    inherit version;

    src = fetchurl {
      url = "https://github.com/ogulcancelik/herdr/releases/download/v${version}/${asset.name}";
      inherit (asset) hash;
    };

    dontUnpack = true;

    installPhase = ''
      runHook preInstall
      install -Dm755 "$src" "$out/bin/herdr"
      runHook postInstall
    '';

    meta = {
      description = "Terminal workspace manager for AI coding agents";
      homepage = "https://herdr.dev";
      changelog = "https://github.com/ogulcancelik/herdr/releases/tag/v${version}";
      license = lib.licenses.agpl3Plus;
      inherit platforms;
      mainProgram = "herdr";
    };
  };
}
