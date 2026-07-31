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

  settingsLib = import ../../../lib/settings/codex.nix;
  commandPolicy = import ../../../lib/agent-command-policy { inherit lib; };
  guardHook = import ../../../lib/agent-command-policy/mk-guard.nix {
    inherit lib pkgs;
    policy = commandPolicy.guardPolicy;
  };
  jsonFormat = pkgs.formats.json { };
  herdrSkillPath = "${codexHome}/skills/herdr/SKILL.md";
  herdrHookPath = "${codexHome}/herdr-agent-state.sh";
  herdrSettings = import ../../../lib/settings/herdr.nix { inherit lib pkgs; };
  herdrHookCommand = herdrSettings.mkSessionHookCommand herdrHookPath;

  codex = pkgs.dotfilesPackages.codex.mkWrappedPackage {
    inherit herdrSkillPath;
  };
  agentConfigHelper = pkgs.callPackage ../../../libexec/agent-config-helper { };

  codexRulesFile = pkgs.writeText "codex-default.rules" commandPolicy.codexRulesContent;
  codexRulesDir =
    pkgs.runCommand "codex-rules"
      {
        nativeBuildInputs = [ pkgs.codex ];
      }
      ''
        export HOME="$TMPDIR/home"
        mkdir -p "$HOME/.codex" "$out"
        cp ${codexRulesFile} "$out/default.rules"
        ln -s "$out" "$HOME/.codex/rules"

        # 実配置と同じ directory symlink を経由し、導入する Codex 自身で
        # Starlark 構文と inline match contract を検証する。
        codex execpolicy check \
          --resolve-host-executables \
          --rules "$HOME/.codex/rules/default.rules" \
          -- rg --files >/dev/null
      '';

  baseMergePayloadJson = jsonFormat.generate "codex-config-merge-base.json" (
    settingsLib.mkMergePayload {
      inherit codexHome;
    }
  );

  emptyHooksJson = jsonFormat.generate "codex-hooks-hcom-disabled.json" { hooks = { }; };
  hcomHooksJson = if enableHcom then "${hcomCodex}/hooks.json" else emptyHooksJson;

  # hcom state key は実環境の hooks.json 絶対パスを含むため、有効時はbuild時に
  # 生成する。古いstateの削除はbase payloadで常に行い、後段で現行hookだけ戻す。
  hcomHooksPayloadJson =
    if enableHcom then
      pkgs.runCommand "codex-hcom-hooks-payload.json"
        {
          nativeBuildInputs = [ agentConfigHelper ];
        }
        ''
          ${lib.getExe agentConfigHelper} codex rekey-hook-state \
            --hooks-path ${lib.escapeShellArg hooksJsonPath} \
            ${hcomCodex}/hooks-state.json \
            > "$out"
        ''
    else
      jsonFormat.generate "codex-hcom-hooks-disabled-payload.json" { };

  hooksJson =
    pkgs.runCommand "codex-hooks.json"
      {
        nativeBuildInputs = [ agentConfigHelper ];
      }
      ''
        ${lib.getExe agentConfigHelper} codex apply-hook-manifest \
          --manifest ${managedHookManifest} \
          ${hcomHooksJson} \
          > "$out"
      '';

  managedHookManifest = jsonFormat.generate "codex-managed-hook-manifest.json" [
    {
      eventName = "sessionStart";
      handlerType = "command";
      matcher = null;
      command = herdrHookCommand;
      timeoutSec = 10;
    }
    {
      eventName = "preToolUse";
      handlerType = "command";
      matcher = "Bash";
      command = guardHook.command;
      timeoutSec = 10;
    }
  ];

  managedHooksStatePayloadJson =
    pkgs.runCommand "codex-managed-hooks-state-payload.json"
      {
        nativeBuildInputs = [ agentConfigHelper ];
      }
      ''
        home="$NIX_BUILD_TOP/home"
        mkdir -p "$home/.codex"
        cp ${hooksJson} "$home/.codex/hooks.json"
        printf '[features]\nhooks = true\n' > "$home/.codex/config.toml"

        export HOME="$home"
        export XDG_CONFIG_HOME="$home/.config"

        ${lib.getExe agentConfigHelper} generate-managed-hook-state \
          --codex-bin ${lib.escapeShellArg "${pkgs.codex}/bin/codex"} \
          --manifest ${managedHookManifest} \
          --hooks-json-path ${lib.escapeShellArg hooksJsonPath} \
          > "$out"
      '';

  # helper には単一 payload を渡すため、Nix 管理設定と hook 生成設定をここで合成する。
  mergePayloadJson =
    pkgs.runCommand "codex-config-merge.json"
      {
        nativeBuildInputs = [ agentConfigHelper ];
      }
      ''
        ${lib.getExe agentConfigHelper} codex merge-payloads \
          ${baseMergePayloadJson} \
          ${hcomHooksPayloadJson} \
          ${managedHooksStatePayloadJson} \
          > "$out"
      '';

  # 検証に使う schema は、実際に導入する Codex CLI と同じ source tag から取り出す。
  # developers.openai.com の live schema を直接固定すると、サイト更新だけで
  # インストール済み Codex と検証 schema がズレるため。
  codexSchema = pkgs.runCommand "codex-config-schema.json" { } ''
    cp ${pkgs.codex.src}/codex-rs/core/config.schema.json $out
  '';
in
{
  home.packages = [ codex ];

  # Codex は読むだけなので read-only symlink で良い。
  home.file.".codex/hooks.json".source = hooksJson;
  home.file.".codex/herdr-agent-state.sh".source = "${herdrCodexIntegration}/herdr-agent-state.sh";

  # user layer の rules directory 全体を read-only symlink にし、対話操作による
  # default.rules への追記ではなく Nix の SSOT だけから変更する。trusted project
  # など別 layer の rules は Codex の仕様どおり追加で読み込まれる。
  home.file.".codex/rules" = {
    source = codexRulesDir;
    recursive = false;
  };

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
  # linkGeneration が ~/.codex と管理対象 symlink を作った後に実行する。
  # 既存ホームに依存すると、新規 NixOS-WSL の初回 activation で mktemp が失敗する。
  home.activation.codexHooksConfig = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    (
      set -e
      candidate=$(${pkgs.coreutils}/bin/mktemp "${configPath}.hooks-XXXXXX")
      trap '${pkgs.coreutils}/bin/rm -f "$candidate"' EXIT
      run ${lib.getExe agentConfigHelper} merge \
        "${configPath}" "${mergePayloadJson}" "$candidate"
      run ${pkgs.taplo}/bin/taplo check "$candidate"
      run ${pkgs.taplo}/bin/taplo check --schema "file://${codexSchema}" "$candidate"
      run ${pkgs.coreutils}/bin/mv -f "$candidate" "${configPath}"
    )
  '';
}
