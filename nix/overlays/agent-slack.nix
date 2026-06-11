final: prev:
let
  # version / hash は nix/pins/agent-slack.json に固定し、
  # `nix run .#update-pins` で自動更新する。
  pin = builtins.fromJSON (builtins.readFile ../pins/agent-slack.json);
  inherit (pin) version;

  system = prev.stdenv.hostPlatform.system;

  asset = pin.assets.${system} or (throw "agent-slack: unsupported system '${system}'");
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
      platforms = builtins.attrNames pin.assets;
      mainProgram = "agent-slack";
      sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    };
  };
}
