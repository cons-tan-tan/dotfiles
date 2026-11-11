let
  base = import ../base/_interface/package-sources.nix;
in
base
// {
  bee = ../bee/_packages/bee;
  browser = ../browser/_packages/agent-browser;
  claudeCode = ../claude/_packages/claude-code;
  codex = ../codex/_packages/codex;
  codexApp = ../codex/_packages/codex-app;
  difit = ../difit/_packages/difit;
  herdr = ../herdr/_packages/herdr;
  hunk = ../hunk/_packages/hunk;
  modernWebGuidance = ../modern-web-guidance/_packages/modern-web-guidance;
  pi = ../pi/_packages/pi;
  slack = ../slack/_packages/agent-slack;
}
