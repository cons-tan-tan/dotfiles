_final: prev:
let
  inherit (prev.stdenv.hostPlatform) system;
  version = prev.watchexec.version;
  target =
    {
      aarch64-darwin = "aarch64-apple-darwin";
      x86_64-darwin = "x86_64-apple-darwin";
    }
    .${system};
  hash =
    {
      aarch64-darwin = "sha256-xeQF3REJlAslEDmNIYKZDBvlkGO5ThHXrOnHtDXLHfE=";
      x86_64-darwin = "sha256-u3S/Myhv9/Md2Odj4Bf7wEGDYNiLrv01vFfWYtKDlOI=";
    }
    .${system};
in
prev.lib.optionalAttrs prev.stdenv.hostPlatform.isDarwin {
  # cctools ld crashes while linking watchexec on GitHub's Darwin runner.
  # Upstream publishes native binaries for both Darwin architectures.
  watchexec = prev.stdenvNoCC.mkDerivation {
    pname = "watchexec";
    inherit version;

    src = prev.fetchurl {
      url = "https://github.com/watchexec/watchexec/releases/download/v${version}/watchexec-${version}-${target}.tar.xz";
      inherit hash;
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
