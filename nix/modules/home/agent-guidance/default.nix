# coding agentが共有する短いglobal guidanceを1つの生成物から配布する。
{ lib, ... }:
let
  commandPolicy = import ../../../lib/agent-command-policy { inherit lib; };
  baseGuidance = builtins.readFile ../../../../claude/CLAUDE.md;
  policyGuidance = lib.concatMapStrings (guidance: "- ${guidance}\n") commandPolicy.guidance;
  separator = lib.optionalString (!lib.hasSuffix "\n" baseGuidance) "\n";
  guidanceText = "${baseGuidance}${separator}${policyGuidance}";
in
{
  home.file = {
    ".claude/CLAUDE.md".text = guidanceText;
    ".codex/AGENTS.md".text = guidanceText;
    ".pi/agent/AGENTS.md".text = guidanceText;
  };
}
