# coding agentが共有するstatic contextを、各toolの読み込み方式に合わせて配布する。
{ lib, ... }:
let
  payload = import ../_interface/payload.nix;
  inherit (payload) contextRoot globalContext rulesDirectory;
  ruleEntries = builtins.readDir rulesDirectory;
  ruleNames = builtins.filter (name: ruleEntries.${name} == "regular" && lib.hasSuffix ".md" name) (
    builtins.attrNames ruleEntries
  );
  stripTrailingNewlines =
    text: if lib.hasSuffix "\n" text then stripTrailingNewlines (lib.removeSuffix "\n" text) else text;
  readContext = path: stripTrailingNewlines (builtins.readFile path);
  combinedContext =
    lib.concatStringsSep "\n\n" (
      [ (readContext globalContext) ] ++ map (name: readContext (rulesDirectory + "/${name}")) ruleNames
    )
    + "\n";
in
{
  home.file = {
    ".agents/context".source = contextRoot;
    ".claude/CLAUDE.md".source = globalContext;
    ".claude/rules".source = rulesDirectory;
    ".codex/AGENTS.md".text = combinedContext;
    ".pi/agent/AGENTS.md".text = combinedContext;
  };
}
