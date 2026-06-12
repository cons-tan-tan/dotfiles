# darwin / linux 共通の flake apps。ホスト固有の build / switch / apply-winget
# は flake.nix 側で合成する。
# 戻り値は { apps, scripts }: scripts は writeShellApplication derivation の
# リストで、checks に束ねてビルド時 shellcheck を CI で強制する。
{ inputs }:
{
  pkgs,
  treefmtWrapper,
}:
let
  mkScript = name: attrs: pkgs.writeShellApplication ({ inherit name; } // attrs);

  updateScript = mkScript "flake-update" {
    text = ''
      echo "Updating flake.lock..."
      nix flake update
      echo "Done! Run 'nix run .#switch' to apply changes."
    '';
  };

  fmtScript = mkScript "treefmt-wrapper" {
    text = ''
      exec ${treefmtWrapper}/bin/treefmt "$@"
    '';
  };

  updatePinsScript = mkScript "update-pins" {
    runtimeInputs = [
      pkgs.curl
      pkgs.jq
      pkgs.gitMinimal
    ];
    text = builtins.readFile ../apps/update-pins.sh;
  };

  # 適用する secrets の宣言。追加はここに 1 エントリ足すだけ
  # (ファイル自体は `sops edit secrets/<name>` で作る。secrets/README.md 参照)。
  # dst は $HOME 相対。dirMode は dst の親ディレクトリに適用する。
  secretsManifest = [
    {
      src = "secrets/ssh-private.conf";
      dst = ".ssh/config.d/50-private.conf";
      mode = "600";
      dirMode = "700";
    }
  ];

  secretsManifestFile = pkgs.writeText "secrets-manifest.json" (builtins.toJSON secretsManifest);

  applySecretsScript = mkScript "apply-secrets" {
    runtimeInputs = [
      pkgs.gnupg
      pkgs.sops
      pkgs.jq
    ];
    text = ''
      # --dry-run: 書き込み先の一覧だけ出して終了する (実環境を触らない検証用)
      dry_run=false
      if [ "''${1:-}" = "--dry-run" ]; then
        dry_run=true
      fi

      failed=0
      while IFS= read -r entry; do
        rel_src=$(jq -r .src <<<"$entry")
        rel_dst=$(jq -r .dst <<<"$entry")
        mode=$(jq -r .mode <<<"$entry")
        dir_mode=$(jq -r .dirMode <<<"$entry")
        src="${inputs.self}/$rel_src"
        dst="$HOME/$rel_dst"

        if [ ! -f "$src" ]; then
          echo "apply-secrets: $rel_src is not in the repo; skipping" >&2
          continue
        fi

        if $dry_run; then
          echo "apply-secrets: would write $dst (mode $mode)"
          continue
        fi

        mkdir -p "$(dirname "$dst")"
        chmod "$dir_mode" "$(dirname "$dst")"

        tmp=$(mktemp "$dst.XXXXXX")
        trap 'rm -f "$tmp"' EXIT
        if ! sops --decrypt "$src" > "$tmp"; then
          # GPG 鍵未導入でも switch を阻害しない方針 (案 B) はファイル単位で維持
          echo "apply-secrets: decryption of $rel_src failed (GPG key not imported?); skipping" >&2
          rm -f "$tmp"
          trap - EXIT
          failed=$((failed + 1))
          continue
        fi
        chmod "$mode" "$tmp"
        mv "$tmp" "$dst"
        trap - EXIT
        echo "apply-secrets: wrote $dst"
      done < <(jq -c '.[]' ${secretsManifestFile})

      if [ "$failed" -gt 0 ]; then
        echo "apply-secrets: $failed file(s) skipped (decryption failed)" >&2
      fi
    '';
  };
in
{
  apps = {
    update = {
      type = "app";
      meta.description = "Update flake.lock to the latest input revisions";
      program = pkgs.lib.getExe updateScript;
    };

    fmt = {
      type = "app";
      meta.description = "Format the repository with treefmt";
      program = pkgs.lib.getExe fmtScript;
    };

    # nix/pins/*.json (hcom / agent-slack / git-wt / codex schema) を upstream の
    # 最新リリースへ同期する。git-wt の vendorHash 計算で `nix build .#git-wt` を
    # 使うため、packages 出力 (flake.nix) に git-wt が必要。
    update-pins = {
      type = "app";
      meta.description = "Sync nix/pins/*.json to the latest upstream releases";
      program = pkgs.lib.getExe updatePinsScript;
    };

    pptx = import ../apps/pptx {
      inherit pkgs;
      inherit (inputs)
        anthropic-skills
        pyproject-build-systems
        pyproject-nix
        uv2nix
        ;
    };

    markdownlint = import ../apps/markdownlint { inherit pkgs; };

    textlint = import ../apps/textlint { inherit pkgs; };

    # sops secrets の明示適用 (案 B: switch と完全分離し、GPG 鍵未導入でも
    # 環境構築が secrets に依存しないことを保証する)。secrets/README.md 参照。
    apply-secrets = {
      type = "app";
      meta.description = "Decrypt sops-managed secrets into place (skips gracefully without the GPG key)";
      program = pkgs.lib.getExe applySecretsScript;
    };
  };

  scripts = [
    updateScript
    fmtScript
    updatePinsScript
    applySecretsScript
  ];
}
