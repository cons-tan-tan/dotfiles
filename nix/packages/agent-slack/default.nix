{
  lib,
  stdenv,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
  agentSlackSource,
  pin ? builtins.fromJSON (builtins.readFile ../../pins/agent-slack.json),
}:
let
  version = (builtins.fromJSON (builtins.readFile "${agentSlackSource}/package.json")).version;
  system = stdenv.hostPlatform.system;
  pinnedAsset = import ../../lib/mk-pinned-asset.nix {
    inherit pin system;
    label = "agent-slack";
  };
  asset = pinnedAsset.asset;
in

# Linux 版は glibc 動的リンク (interpreter /lib64/ld-linux-*.so.2) なので、
# autoPatchelfHook で Nix の glibc に向ける (Ubuntu-WSL では素でも動くが、
# NixOS では patch なしだと実行できない)。autoPatchelfHook は stdenv の
# dynamic linker 情報を使うため Linux では full stdenv にする。
(if stdenv.isLinux then stdenv else stdenvNoCC).mkDerivation {
  pname = "agent-slack";
  inherit version;

  src = fetchurl {
    url = "https://github.com/stablyai/agent-slack/releases/download/v${version}/${asset.name}";
    inherit (asset) hash;
  };

  dontUnpack = true;

  nativeBuildInputs = lib.optionals stdenv.isLinux [ autoPatchelfHook ];
  # libsecret-1.so.0 は dlopen 参照 (DT_NEEDED ではない) なので不要。
  # 必要になったら buildInputs に libsecret を追加する。

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/agent-slack"
    runHook postInstall
  '';

  meta = with lib; {
    description = "Slack automation CLI for AI agents";
    homepage = "https://github.com/stablyai/agent-slack";
    license = licenses.mit;
    platforms = pinnedAsset.platforms;
    mainProgram = "agent-slack";
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
  };
}
