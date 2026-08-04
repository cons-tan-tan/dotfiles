# darwin / linux 共通の flake apps。ホスト固有のappは
# modules/features/apps/host.nix側で合成する。
# 戻り値は { apps, validations, validationsByName, groups }。
# groups は Den feature が所有する app だけを選べる境界で、全体の
# apps/validations は同じ group から導出する。
{ inputs, username }:
{
  pkgs,
  treefmtWrapper,
}:
let
  lib = pkgs.lib;
  appSet = import ./mk-app-set.nix { inherit lib; };
  mkScript = name: attrs: pkgs.writeShellApplication ({ inherit name; } // attrs);
  nixCustomSettings = import ../nix-custom-settings.nix { inherit lib username; };

  nixCustomSettingsFile = pkgs.writeText "dotfiles-nix-custom.conf" nixCustomSettings.text;
  updatePinsCore = pkgs.callPackage ../../apps/update-pins { };
  applySecretsCore = pkgs.callPackage ../../apps/apply-secrets { };
  applyNixSettingsCore = pkgs.callPackage ../../apps/apply-nix-settings { };

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
      pkgs.cargo
      pkgs.curl
      pkgs.gitMinimal
      pkgs.nix
    ];
    text = ''
      exec ${lib.getExe updatePinsCore} "$@"
    '';
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
  # apply-secrets only resolves the declared manifest sources. Keeping the
  # runtime root narrow avoids rebuilding the public wrapper for unrelated
  # repository changes while preserving each repo-relative path under secrets/.
  secretsSource = lib.fileset.toSource {
    root = ../../..;
    fileset = lib.fileset.unions (map (entry: ../../.. + "/${entry.src}") secretsManifest);
  };

  applySecretsScript = mkScript "apply-secrets" {
    runtimeInputs = [ pkgs.gnupg ];
    text = ''
      export APPLY_SECRETS_ROOT=${secretsSource}
      export APPLY_SECRETS_MANIFEST=${secretsManifestFile}
      export APPLY_SECRETS_SOPS_BIN=${lib.getExe pkgs.sops}
      exec ${lib.getExe applySecretsCore} "$@"
    '';
  };

  applyNixSettingsScript = mkScript "apply-nix-settings" {
    text = ''
      export APPLY_NIX_SETTINGS_SNIPPET=${nixCustomSettingsFile}
      exec ${lib.getExe applyNixSettingsCore} "$@"
    '';
  };
  groups = {
    maintenance = appSet.mkAppSet {
      entries = {
        update = {
          description = "Update flake.lock to the latest input revisions";
          script = updateScript;
        };

        fmt = {
          description = "Format the repository with treefmt";
          script = fmtScript;
        };

        apply-nix-settings = {
          description = "Sync root-level Nix daemon settings into /etc/nix/nix.custom.conf";
          script = applyNixSettingsScript;
        };
      };
    };

    update-pins = appSet.mkAppSet {
      entries.update-pins = {
        description = "Sync nix/pins/*.json to the latest upstream state";
        script = updatePinsScript;
      };
    };

    secrets = appSet.mkAppSet {
      entries.apply-secrets = {
        description = "Decrypt sops-managed secrets into place (skips gracefully without the GPG key)";
        script = applySecretsScript;
      };
    };

    lint = appSet.mkAppSet {
      entries = {
        pptx = import ../../apps/pptx {
          inherit pkgs;
          inherit (inputs)
            anthropic-skills
            pyproject-build-systems
            pyproject-nix
            uv2nix
            ;
        };

        markdownlint = import ../../apps/markdownlint { inherit pkgs; };

        textlint = import ../../apps/textlint { inherit pkgs; };
      };
    };
  };

  combined = appSet.mergeAppSets (builtins.attrValues groups);
in
combined
// {
  inherit groups;
}
