let
  overlay = (import ../_interface/overlays.nix).llmAgents {
    packages = {
      "test-system" = {
        ccusage = "selected-ccusage";
        claude-code = "selected-claude-code";
        codex = "selected-codex";
        ignored = "selected-ignored";
        opencode = "selected-opencode";
        pi = "selected-pi";
      };
      "other-system" = {
        ccusage = "other-ccusage";
        claude-code = "other-claude-code";
        codex = "other-codex";
        opencode = "other-opencode";
        pi = "other-pi";
      };
    };
  };
  result = overlay { marker = "final"; } {
    stdenv.hostPlatform.system = "test-system";
  };
in
{
  testLlmAgentsOnlyExposeBridgedPackages = {
    expr = builtins.attrNames result;
    expected = [
      "ccusage"
      "claude-code"
      "codex"
      "opencode"
      "pi"
    ];
  };

  testLlmAgentsUseHostSystemPackages = {
    expr = result;
    expected = {
      ccusage = "selected-ccusage";
      claude-code = "selected-claude-code";
      codex = "selected-codex";
      opencode = "selected-opencode";
      pi = "selected-pi";
    };
  };
}
