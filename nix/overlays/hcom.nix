final: prev:
let
  # version / hash は nix/pins/hcom.json に固定し、`nix run .#update-pins` で
  # 自動更新する (flake input hcom-src も同時に更新される)。
  # Linux uses the static musl build: no glibc dependency, so autoPatchelfHook
  # is unnecessary. macOS has no musl variant, so use the native darwin build.
  pin = builtins.fromJSON (builtins.readFile ../pins/hcom.json);
  inherit (pin) version;

  system = prev.stdenv.hostPlatform.system;
  asset = pin.assets.${system} or (throw "hcom: unsupported system '${system}'");
in
{
  hcom = prev.stdenvNoCC.mkDerivation {
    pname = "hcom";
    inherit version;

    src = prev.fetchurl {
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

    meta = with prev.lib; {
      description = "Let AI agents message, watch, and spawn each other across terminals";
      homepage = "https://github.com/aannoo/hcom";
      license = licenses.mit;
      platforms = builtins.attrNames pin.assets;
      mainProgram = "hcom";
      sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    };
  };

  # Run hcom's own `hooks add` rather than hand-copying or re-implementing its
  # output format, so the definitions track the packaged version automatically.
  # Claude has no hook-trust mechanism, so its emitted settings are usable as-is.
  hcom-claude-hooks =
    prev.runCommand "hcom-claude-hooks.json"
      {
        nativeBuildInputs = [
          final.hcom
          prev.jq
        ];
      }
      ''
        export HOME="$TMPDIR/home"
        mkdir -p "$HOME/.claude"
        hcom hooks add claude >/dev/null 2>&1 || true
        if [ ! -f "$HOME/.claude/settings.json" ]; then
          echo "hcom did not generate ~/.claude/settings.json" >&2
          exit 1
        fi
        jq '{hooks, env, permissions}' "$HOME/.claude/settings.json" > "$out"
      '';

  # trusted_hash is computed by codex's own (undocumented) algorithm, so rather
  # than re-implement it we run hcom+codex and let codex's app-server RPC produce
  # it. Shaping uses yj/jq to avoid pulling in python. The state key embeds an
  # absolute path that differs between sandbox and $HOME, so we re-key by event
  # label here and rebuild the real path in codex/default.nix.
  hcom-codex-hooks =
    prev.runCommand "hcom-codex-hooks"
      {
        nativeBuildInputs = [
          final.hcom
          final.codex
          prev.yj
          prev.jq
        ];
      }
      ''
        export HOME="$TMPDIR/home"
        mkdir -p "$HOME/.codex" "$out"
        hcom hooks add codex >/dev/null 2>&1 || true
        test -f "$HOME/.codex/hooks.json" || { echo "hcom did not generate hooks.json" >&2; exit 1; }
        test -f "$HOME/.codex/config.toml" || { echo "hcom did not generate config.toml" >&2; exit 1; }
        cp "$HOME/.codex/hooks.json" "$out/hooks.json"
        yj -tj < "$HOME/.codex/config.toml" \
          | jq '.hooks.state
                | to_entries
                | map({ key: (.key | split(":")[-3]), value: .value })
                | from_entries' \
          > "$out/hooks-state.json"
      '';
}
