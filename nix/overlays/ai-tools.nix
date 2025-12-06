final: prev: {
  # AI tools from nix-ai-tools (https://github.com/numtide/nix-ai-tools)
  inherit (prev._ai-tools.packages.${prev.stdenv.hostPlatform.system})
    ccusage
    ccusage-codex
    ;
}
