{
  agentConfigHelper,
  baseMergePayloadJson,
  codex,
  codexSchema,
  coreutils,
  hooksJson,
  hooksJsonPath,
  lib,
  managedHookManifest,
  runCommand,
  taplo,
  writeShellApplication,
}:
let
  generateState = writeShellApplication {
    name = "codex-managed-hooks-state";
    runtimeInputs = [ coreutils ];
    text = ''
      config_helper=${lib.escapeShellArg (lib.getExe agentConfigHelper)}
      codex_bin=${lib.escapeShellArg "${codex}/bin/codex"}
      hooks_source=${lib.escapeShellArg hooksJson}
      hooks_path=${lib.escapeShellArg hooksJsonPath}
      manifest=${lib.escapeShellArg managedHookManifest}
      ${builtins.readFile ../_scripts/generate-hooks-state.sh}
    '';
  };

  mergePayload = runCommand "codex-config-merge.json" { } ''
    ${lib.getExe generateState} > hooks-state.json
    ${lib.getExe agentConfigHelper} codex merge-payloads \
      ${baseMergePayloadJson} hooks-state.json > "$out"
  '';

  reconcile = writeShellApplication {
    name = "codex-config-reconcile";
    runtimeInputs = [
      coreutils
      taplo
    ];
    text = ''
      config_helper=${lib.escapeShellArg (lib.getExe agentConfigHelper)}
      base_payload=${lib.escapeShellArg baseMergePayloadJson}
      config_schema=${lib.escapeShellArg codexSchema}
      ${builtins.readFile ../_scripts/reconcile-config.sh}
    '';
  };
in
{
  inherit generateState mergePayload reconcile;
}
