# darwin / linux 共通の flake apps。ホスト固有の build / switch / apply-winget
# は flake.nix 側で合成する。
# 戻り値は { apps, scripts }: scripts は writeShellApplication derivation の
# リストで、checks に束ねてビルド時 shellcheck を CI で強制する。
{ inputs, username }:
{
  pkgs,
  treefmtWrapper,
}:
let
  lib = pkgs.lib;
  mkScript = name: attrs: pkgs.writeShellApplication ({ inherit name; } // attrs);
  nixCustomSettings = import ./nix-custom-settings.nix { inherit lib username; };

  nixCustomSettingsFile = pkgs.writeText "dotfiles-nix-custom.conf" nixCustomSettings.text;

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
      pkgs.nodejs
      pkgs.python3
      pkgs.gnutar
      pkgs.gzip
      pkgs.unzip
    ];
    text = builtins.readFile ../apps/update-pins.sh;
  };

  # 適用する secrets の宣言。追加はここに 1 エントリ足すだけ
  # (ファイル自体は `sops edit secrets/<name>` で作る。secrets/README.md 参照)。
  # dst は $HOME 相対。dirMode は dst の親ディレクトリに適用する。
  secretsManifest = [
    {
      src = "secrets/ssh-private.yaml";
      dst = ".ssh/config.d/50-private.conf";
      format = "ssh-config-yaml";
      mode = "600";
      dirMode = "700";
    }
  ];

  secretsManifestFile = pkgs.writeText "secrets-manifest.json" (builtins.toJSON secretsManifest);

  applySecretsRenderers = pkgs.linkFarm "apply-secrets-renderers" [
    {
      name = "ssh-config-yaml.jq";
      path = ../apps/apply-secrets/renderers/ssh-config-yaml.jq;
    }
  ];

  applySecretsScript = mkScript "apply-secrets" {
    runtimeInputs = [
      pkgs.gnupg
      pkgs.sops
      pkgs.jq
    ];
    text = ''
      export APPLY_SECRETS_ROOT=${inputs.self}
      export APPLY_SECRETS_MANIFEST=${secretsManifestFile}
      export APPLY_SECRETS_RENDERERS_DIR=${applySecretsRenderers}
      ${builtins.readFile ../apps/apply-secrets/apply-secrets.sh}
    '';
  };

  applyNixSettingsScript = mkScript "apply-nix-settings" {
    runtimeInputs = [
      pkgs.coreutils
      pkgs.diffutils
      pkgs.gawk
      pkgs.gnugrep
    ];
    text = ''
      export APPLY_NIX_SETTINGS_SNIPPET=${nixCustomSettingsFile}
      ${builtins.readFile ../apps/apply-nix-settings.sh}
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

    # nix/pins/*.json (hcom / agent-slack / git-wt / herdr / schema) を upstream の
    # 最新状態へ同期する。git-wt の vendorHash 計算で `nix build .#git-wt` を
    # 使うため、packages 出力 (flake.nix) に git-wt が必要。
    update-pins = {
      type = "app";
      meta.description = "Sync nix/pins/*.json to the latest upstream state";
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

    apply-nix-settings = {
      type = "app";
      meta.description = "Sync root-level Nix daemon settings into /etc/nix/nix.custom.conf";
      program = pkgs.lib.getExe applyNixSettingsScript;
    };
  };

  scripts = [
    updateScript
    fmtScript
    updatePinsScript
    applySecretsScript
    applyNixSettingsScript
  ];
}
