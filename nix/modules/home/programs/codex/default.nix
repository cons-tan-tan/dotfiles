{
  config,
  pkgs,
  lib,
  ...
}:
let
  # 生成は overlay (hcom+codex を実行) に任せ参照のみ — Codex の内部仕様 (hash
  # アルゴリズム等) をこちらで再実装しないため。
  hcomCodex = pkgs.hcom-codex-hooks;

  codexHome = "${config.home.homeDirectory}/.codex";
  configPath = "${codexHome}/config.toml";
  hooksJsonPath = "${codexHome}/hooks.json";

  settingsLib = import ../../../../lib/settings/codex.nix { };
  jsonFormat = pkgs.formats.json { };

  baseMergePayloadJson = jsonFormat.generate "codex-config-merge-base.json" (
    settingsLib.mkMergePayload {
      inherit codexHome;
      herdrMarketplace = "${pkgs.herdr-codex-marketplace}";
    }
  );

  # hcom state key は実環境の hooks.json 絶対パスを含むため、build 時に生成する。
  # hcomCodex の生成 JSON を eval 時に読む (IFD) と異種プラットフォーム向け構成の
  # 評価 (nix flake check 等) が壊れる。
  hcomHooksPayloadJson =
    pkgs.runCommand "codex-hcom-hooks-payload.json"
      {
        nativeBuildInputs = [ pkgs.jq ];
      }
      ''
        jq --arg hooksJsonPath ${lib.escapeShellArg hooksJsonPath} '
          { hooks: { state: (to_entries
                              | map({ key: ($hooksJsonPath + ":" + .key + ":0:0"), value: .value })
                              | from_entries) } }
        ' ${hcomCodex}/hooks-state.json > $out
      '';

  # merge.py には単一 payload を渡すため、Nix 管理設定と hcom 生成設定をここで合成する。
  mergePayloadJson =
    pkgs.runCommand "codex-config-merge.json"
      {
        nativeBuildInputs = [ pkgs.jq ];
      }
      ''
        jq -s '.[0] * .[1]' ${baseMergePayloadJson} ${hcomHooksPayloadJson} > $out
      '';

  # 検証に使う schema は、実際に導入する Codex CLI と同じ source tag から取り出す。
  # developers.openai.com の live schema を直接固定すると、サイト更新だけで
  # インストール済み Codex と検証 schema がズレるため。
  codexSchema = pkgs.runCommand "codex-config-schema.json" { } ''
    cp ${pkgs.codex.src}/codex-rs/core/config.schema.json $out
  '';

  pythonWithTomlkit = pkgs.python3.withPackages (p: [ p.tomlkit ]);
in
{
  # Codex は読むだけなので read-only symlink で良い。
  home.file.".codex/hooks.json".source = "${hcomCodex}/hooks.json";

  # programs.codex は config.toml を read-only symlink で置き Codex の動的書き込み
  # ([projects]/[notice]/[tui]) を壊すため使わない。候補で検証してから mv するのは
  # 検証を通った設定だけを本番に置く (落ちても本番を壊さない) ため。候補名を mktemp
  # で一意にするのは固定名だと並行 switch が同じ候補を共有し TOCTOU になるため。
  # サブシェル + set -e + trap は、後始末を他フラグメントへ漏らさず、検証失敗時に
  # 本番へ mv させないため。
  home.activation.codexHcomHooks = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    (
      set -e
      candidate=$(${pkgs.coreutils}/bin/mktemp "${configPath}.hcom-XXXXXX")
      trap '${pkgs.coreutils}/bin/rm -f "$candidate"' EXIT
      run ${pythonWithTomlkit}/bin/python3 ${./merge.py} \
        "${configPath}" "${mergePayloadJson}" "$candidate"
      run ${pkgs.taplo}/bin/taplo check "$candidate"
      run ${pkgs.taplo}/bin/taplo check --schema "file://${codexSchema}" "$candidate"
      run ${pkgs.coreutils}/bin/mv -f "$candidate" "${configPath}"
    )
  '';
}
