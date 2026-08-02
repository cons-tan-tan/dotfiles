{ lib, llmAgents }:

# flake.nix の nixConfig は直接の attrset を要求するため、対象リスト全体が
# cache-settings.nix と乖離していないことを通常の Nix import で検証する。
let
  cache = import ./cache-settings.nix;
  flakeConfig = (import ../../flake.nix).nixConfig;
  rootLock = lib.importJSON ../../flake.lock;
  upstreamLock = lib.importJSON (llmAgents + "/flake.lock");

  resolvedDirectInputs =
    lock: rootNode: lib.mapAttrs (_name: node: lock.nodes.${node}.locked) lock.nodes.${rootNode}.inputs;

  llmAgentsNode = rootLock.nodes.root.inputs.llm-agents;
in
{
  testFlakeNixConfigContainsSubstituters = {
    expr = flakeConfig.extra-substituters;
    expected = [
      "https://cache.nixos.org"
      cache.numtideSubstituter
      cache.nixCommunitySubstituter
    ];
  };

  testFlakeNixConfigContainsKeys = {
    expr = flakeConfig.extra-trusted-public-keys;
    expected = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      cache.numtideTrustedPublicKey
      cache.nixCommunityTrustedPublicKey
    ];
  };

  # Nix が新しく解決する推移的 input は上流 flake.lock より先へ進み得る。
  # 上流 CI と同じ store path を保ち、Numtide cache の miss を検知する。
  testLlmAgentsInputsMatchUpstreamLock = {
    expr = resolvedDirectInputs rootLock llmAgentsNode;
    expected = resolvedDirectInputs upstreamLock "root";
  };
}
