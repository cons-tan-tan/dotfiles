{
  config,
  pkgs,
  lib,
  ...
}:
let
  enableHcom = config.dotfiles.hcom.enable;

  # 生成は package (hcom+codex を実行) に任せ参照のみ — Codex の内部仕様 (hash
  # アルゴリズム等) をこちらで再実装しないため。
  hcomCodex = pkgs.dotfilesPackages.hcom.integrations.codexHooks;
  herdrCodexIntegration = pkgs.dotfilesPackages.herdr.integrations.codex;

  codexHome = "${config.home.homeDirectory}/.codex";
  configPath = "${codexHome}/config.toml";
  hooksJsonPath = "${codexHome}/hooks.json";

  settingsLib = import ../../../../lib/settings/codex.nix { };
  jsonFormat = pkgs.formats.json { };
  herdrSkillPath = "${codexHome}/skills/herdr/SKILL.md";
  herdrHookPath = "${codexHome}/herdr-agent-state.sh";
  herdrSettings = import ../../../../lib/settings/herdr.nix { inherit lib pkgs; };
  herdrHookCommand = herdrSettings.mkSessionHookCommand herdrHookPath;

  codex = pkgs.dotfilesPackages.codex.mkWrappedPackage {
    inherit herdrSkillPath;
  };

  baseMergePayloadJson = jsonFormat.generate "codex-config-merge-base.json" (
    settingsLib.mkMergePayload {
      inherit codexHome;
    }
  );

  emptyHooksJson = jsonFormat.generate "codex-hooks-hcom-disabled.json" { hooks = { }; };
  hcomHooksJson = if enableHcom then "${hcomCodex}/hooks.json" else emptyHooksJson;

  # hcom state key は実環境の hooks.json 絶対パスを含むため、有効時はbuild時に
  # 生成する。無効時は同じhooks.jsonに属する既存stateをprefixで削除し、後段で
  # Herdr分だけを再投入する。
  hcomHooksPayloadJson =
    if enableHcom then
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
        ''
    else
      jsonFormat.generate "codex-hcom-hooks-disabled-payload.json" {
        __delete_prefixes = [
          {
            path = [
              "hooks"
              "state"
            ];
            prefix = "${hooksJsonPath}:";
          }
        ];
      };

  hooksJson =
    pkgs.runCommand "codex-hooks.json"
      {
        nativeBuildInputs = [ pkgs.jq ];
      }
      ''
        jq --arg command ${lib.escapeShellArg herdrHookCommand} '
          .hooks.SessionStart = ((.hooks.SessionStart // []) + [
            {
              hooks: [
                {
                  command: $command,
                  timeout: 10,
                  type: "command"
                }
              ]
            }
          ])
        ' ${hcomHooksJson} > $out
      '';

  herdrHooksStatePayloadJson =
    pkgs.runCommand "codex-herdr-hooks-state-payload.json"
      {
        nativeBuildInputs = [ pkgs.python3 ];
      }
      ''
        home="$NIX_BUILD_TOP/home"
        mkdir -p "$home/.codex"
        cp ${hooksJson} "$home/.codex/hooks.json"
        printf '[features]\nhooks = true\n' > "$home/.codex/config.toml"

        export HOME="$home"
        export XDG_CONFIG_HOME="$home/.config"

        ${pkgs.python3}/bin/python3 ${./generate_herdr_hook_state.py} \
          --codex-bin ${lib.escapeShellArg "${pkgs.codex}/bin/codex"} \
          --hook-command ${lib.escapeShellArg herdrHookCommand} \
          --hooks-json-path ${lib.escapeShellArg hooksJsonPath} \
          > "$out"
      '';

  # merge.py には単一 payload を渡すため、Nix 管理設定と hook 生成設定をここで合成する。
  mergePayloadJson =
    pkgs.runCommand "codex-config-merge.json"
      {
        nativeBuildInputs = [ pkgs.jq ];
      }
      ''
        jq -s '.[0] * .[1] * .[2]' \
          ${baseMergePayloadJson} \
          ${hcomHooksPayloadJson} \
          ${herdrHooksStatePayloadJson} \
          > $out
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
  home.packages = [ codex ];

  # Codex は読むだけなので read-only symlink で良い。
  home.file.".codex/hooks.json".source = hooksJson;
  home.file.".codex/herdr-agent-state.sh".source = "${herdrCodexIntegration}/herdr-agent-state.sh";

  # Herdr の Codex plugin enable は SessionFlags (`-c`) で反転できないため、
  # Codex では通常 skill として配置し、skills.config だけを wrapper から反転する。
  # Codex の skill scanner は symlink ファイルを SKILL.md として読まないが、
  # symlink ディレクトリは辿るため、recursive 展開せず directory symlink にする。
  home.file.".codex/skills/herdr".source = pkgs.dotfilesPackages.herdr.agent.skill;

  # programs.codex は config.toml を read-only symlink で置き Codex の動的書き込み
  # ([projects]/[notice]/[tui]) を壊すため使わない。候補で検証してから mv するのは
  # 検証を通った設定だけを本番に置く (落ちても本番を壊さない) ため。候補名を mktemp
  # で一意にするのは固定名だと並行 switch が同じ候補を共有し TOCTOU になるため。
  # サブシェル + set -e + trap は、後始末を他フラグメントへ漏らさず、検証失敗時に
  # 本番へ mv させないため。
  home.activation.codexHooksConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    (
      set -e
      candidate=$(${pkgs.coreutils}/bin/mktemp "${configPath}.hooks-XXXXXX")
      trap '${pkgs.coreutils}/bin/rm -f "$candidate"' EXIT
      run ${pythonWithTomlkit}/bin/python3 ${./merge.py} \
        "${configPath}" "${mergePayloadJson}" "$candidate"
      run ${pkgs.taplo}/bin/taplo check "$candidate"
      run ${pkgs.taplo}/bin/taplo check --schema "file://${codexSchema}" "$candidate"
      run ${pkgs.coreutils}/bin/mv -f "$candidate" "${configPath}"
    )
  '';
}
