_final: prev:
let
  inherit (prev.stdenv.hostPlatform) system;
  pin = builtins.fromJSON (builtins.readFile ../pins/watchexec.json);
  inherit (pin) version;
  asset = pin.assets.${system} or (throw "watchexec: unsupported system '${system}'");
  assetName = "watchexec-${version}-${asset.target}.tar.xz";
in
prev.lib.optionalAttrs prev.stdenv.hostPlatform.isDarwin {
  # cctools ld crashes while linking watchexec on GitHub's Darwin runner.
  # Upstream publishes native binaries for both Darwin architectures.
  watchexec = prev.stdenvNoCC.mkDerivation {
    pname = "watchexec";
    inherit version;

    src = prev.fetchurl {
      url = "https://github.com/watchexec/watchexec/releases/download/v${version}/${assetName}";
      inherit (asset) hash;
    };

    installPhase = ''
      runHook preInstall

      install -Dm755 watchexec "$out/bin/watchexec"
      install -Dm644 watchexec.1 "$out/share/man/man1/watchexec.1"
      install -Dm644 completions/bash "$out/share/bash-completion/completions/watchexec"
      install -Dm644 completions/fish "$out/share/fish/vendor_completions.d/watchexec.fish"
      install -Dm644 completions/zsh "$out/share/zsh/site-functions/_watchexec"

      runHook postInstall
    '';

    meta = prev.watchexec.meta // {
      sourceProvenance = with prev.lib.sourceTypes; [ binaryNativeCode ];
    };
  };
}
