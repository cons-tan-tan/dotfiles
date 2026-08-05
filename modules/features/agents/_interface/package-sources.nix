let
  base = import ../base/_interface/package-sources.nix;
in
base
// {
  browser = ../browser/_packages/agent-browser;
  claudeCode = ../claude/_packages/claude-code;
  codex = ../codex/_packages/codex;
  codexApp = ../codex/_packages/codex-app;
  difit = ../difit/_packages/difit;
  hcom = ../hcom/_packages/hcom;
  herdr = ../herdr/_packages/herdr;
  hunk = ../hunk/_packages/hunk;
  pi = ../pi/_packages/pi;
  slack = ../slack/_packages/agent-slack;
}
