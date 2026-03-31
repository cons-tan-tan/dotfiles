final: prev:
let
  llm = prev._llm-agents.packages.${prev.stdenv.hostPlatform.system};
in
{
  # LLM agents from llm-agents.nix (https://github.com/numtide/llm-agents.nix)
  inherit (llm)
    codex
    opencode
    ccusage
    ccusage-codex
    agent-browser
    ;

  # claude-code with nodejs in PATH (required by codex-plugin-cc)
  claude-code = llm.claude-code.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.makeWrapper ];
    postFixup = (old.postFixup or "") + ''
      wrapProgram $out/bin/.claude-wrapped \
        --prefix PATH : ${final.nodejs}/bin
    '';
  });
}
