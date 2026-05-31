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

  # merge.py に hcom 固有の知識を持たせないため、merge 内容は全てここ (Nix) で
  # 組み立てて渡す。state key の絶対パスは sandbox では決まらないので label から
  # 実環境パスを組み立てる。
  hooksState = builtins.fromJSON (builtins.readFile "${hcomCodex}/hooks-state.json");
  mergePayload = {
    features.hooks = true;
    hooks.state = lib.mapAttrs' (
      label: value: lib.nameValuePair "${hooksJsonPath}:${label}:0:0" value
    ) hooksState;
  };
  mergePayloadJson = (pkgs.formats.json { }).generate "codex-hcom-merge.json" mergePayload;

  # オフライン・再現的に検証するため schema を store に固定 (activation 時にネット
  # アクセスしない)。更新は nix-prefetch-url で hash を取り直す。
  codexSchema = pkgs.fetchurl {
    url = "https://developers.openai.com/codex/config-schema.json";
    sha256 = "1nbv5cqlia4fyy4zf7m1d9n3c5bp9w7iw64bzpgs0wx1i7fgr7nh";
  };

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
