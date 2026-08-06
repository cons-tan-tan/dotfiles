{
  mkPinnedAsset,
  pin ? builtins.fromJSON (builtins.readFile ./pin.json),
  updateScript ? null,
}:
_final: prev:
let
  updater =
    if updateScript != null then
      updateScript
    else
      prev.callPackage ../_scripts/update.nix {
        ghApiGet = prev.dotfilesPackages.gh-api-get;
      };
  updatePassthru =
    previous:
    previous
    // {
      updateScript = if builtins.isString updater then updater else prev.lib.getExe updater;
      updateScriptName = "watchexec";
      updateScriptDescription = "Update pinned Watchexec Darwin release assets";
    };
  inherit (prev.stdenv.hostPlatform) system;
  inherit (pin) version;
  pinnedAsset = mkPinnedAsset {
    inherit pin system;
    label = "watchexec";
  };
  asset = pinnedAsset.asset;
  assetName = "watchexec-${version}-${asset.target}.tar.xz";
  darwinPackage = prev.stdenvNoCC.mkDerivation {
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

    passthru = updatePassthru (prev.watchexec.passthru or { });

    meta = prev.watchexec.meta // {
      sourceProvenance = with prev.lib.sourceTypes; [ binaryNativeCode ];
    };
  };
in
{
  # cctools ld crashes while linking watchexec on GitHub's Darwin runner.
  # Upstream publishes native binaries for both Darwin architectures. Other
  # systems keep nixpkgs' build and receive only this repository's updater.
  watchexec =
    if prev.stdenv.hostPlatform.isDarwin then
      darwinPackage
    else
      prev.watchexec.overrideAttrs (old: {
        passthru = updatePassthru (old.passthru or { });
      });
}
