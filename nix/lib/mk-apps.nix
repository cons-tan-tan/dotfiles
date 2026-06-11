# darwin / linux 共通の flake apps。ホスト固有の build / switch / winget-apply
# は flake.nix 側で合成する。
{ inputs }:
{
  pkgs,
  treefmtWrapper,
}:
{
  update = {
    type = "app";
    meta.description = "Update flake.lock to the latest input revisions";
    program = toString (
      pkgs.writeShellScript "flake-update" ''
        set -e
        echo "Updating flake.lock..."
        nix flake update
        echo "Done! Run 'nix run .#switch' to apply changes."
      ''
    );
  };

  fmt = {
    type = "app";
    meta.description = "Format the repository with treefmt";
    program = toString (
      pkgs.writeShellScript "treefmt-wrapper" ''
        exec ${treefmtWrapper}/bin/treefmt "$@"
      ''
    );
  };

  # nix/pins/*.json (hcom / agent-slack / git-wt / codex schema) を upstream の
  # 最新リリースへ同期する。git-wt の vendorHash 計算で `nix build .#git-wt` を
  # 使うため、packages 出力 (flake.nix) に git-wt が必要。
  update-pins = {
    type = "app";
    meta.description = "Sync nix/pins/*.json to the latest upstream releases";
    program = pkgs.lib.getExe (
      pkgs.writeShellApplication {
        name = "update-pins";
        runtimeInputs = [
          pkgs.curl
          pkgs.jq
          pkgs.gitMinimal
        ];
        text = builtins.readFile ../apps/update-pins.sh;
      }
    );
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
    program = toString (
      pkgs.writeShellScript "apply-secrets" ''
        set -euo pipefail
        export PATH=${pkgs.lib.makeBinPath [ pkgs.gnupg ]}:$PATH

        src=${inputs.self}/secrets/ssh-private.conf
        dst="$HOME/.ssh/config.d/50-private.conf"

        if [ ! -f "$src" ]; then
          echo "apply-secrets: secrets/ssh-private.conf is not in the repo yet; nothing to apply" >&2
          exit 0
        fi

        mkdir -p "$HOME/.ssh/config.d"
        chmod 700 "$HOME/.ssh/config.d"

        tmp=$(mktemp "$dst.XXXXXX")
        trap 'rm -f "$tmp"' EXIT
        if ! ${pkgs.sops}/bin/sops --decrypt "$src" > "$tmp"; then
          echo "apply-secrets: decryption failed (GPG key not imported?); skipping" >&2
          exit 0
        fi
        chmod 600 "$tmp"
        mv "$tmp" "$dst"
        trap - EXIT
        echo "apply-secrets: wrote $dst"
      ''
    );
  };
}
