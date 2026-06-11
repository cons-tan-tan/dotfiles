final: prev:
let
  version = "0.8.0";

  assetBySystem = {
    aarch64-darwin = {
      name = "agent-slack-darwin-arm64";
      hash = "sha256-sZG4hRnuXyqZq1xU+IprjR0R8jk33m2Ew0bRSQCng5g=";
    };
    x86_64-darwin = {
      name = "agent-slack-darwin-x64";
      hash = "sha256-3M3+rViZ3naVArpuF82TipE03TRdZr7oeecoxn6WDaQ=";
    };
    aarch64-linux = {
      name = "agent-slack-linux-arm64";
      hash = "sha256-qL75kq8q1ykJDsZVhGdX09R3CzsJCI0dntPkSlImbs8=";
    };
    x86_64-linux = {
      name = "agent-slack-linux-x64";
      hash = "sha256-P7sJAi0FNiihJihS6yKCVbxm3peJYZjanIRvGciR9fs=";
    };
  };

  system = prev.stdenv.hostPlatform.system;

  asset = assetBySystem.${system} or (throw "agent-slack: unsupported system '${system}'");
in
{
  # Linux 版は glibc 動的リンク (interpreter /lib64/ld-linux-*.so.2) なので、
  # autoPatchelfHook で Nix の glibc に向ける (Ubuntu-WSL では素でも動くが、
  # NixOS では patch なしだと実行できない)。autoPatchelfHook は stdenv の
  # dynamic linker 情報を使うため Linux では full stdenv にする。
  agent-slack = (if prev.stdenv.isLinux then prev.stdenv else prev.stdenvNoCC).mkDerivation {
    pname = "agent-slack";
    inherit version;

    src = prev.fetchurl {
      url = "https://github.com/stablyai/agent-slack/releases/download/v${version}/${asset.name}";
      inherit (asset) hash;
    };

    dontUnpack = true;

    nativeBuildInputs = prev.lib.optionals prev.stdenv.isLinux [ prev.autoPatchelfHook ];
    # libsecret-1.so.0 は dlopen 参照 (DT_NEEDED ではない) なので不要。
    # 必要になったら buildInputs に prev.libsecret を追加する。

    installPhase = ''
      runHook preInstall
      install -Dm755 "$src" "$out/bin/agent-slack"
      runHook postInstall
    '';

    meta = with prev.lib; {
      description = "Slack automation CLI for AI agents";
      homepage = "https://github.com/stablyai/agent-slack";
      license = licenses.mit;
      platforms = builtins.attrNames assetBySystem;
      mainProgram = "agent-slack";
      sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    };
  };
}
