{
  hostPlatform,
  inputs,
  lib,
  pkgs,
}:
let
  aws = import ./aws {
    inherit (pkgs) callPackage;
  };
  hcom = import ./hcom {
    inherit (pkgs) callPackage;
    hcomSource = inputs.hcom-src;
  };
  codex = import ./codex {
    inherit (pkgs) callPackage;
    inherit (pkgs) codex;
  };
  herdr = import ./herdr {
    inherit (pkgs) callPackage;
  };
  pi = import ./pi {
    inherit (pkgs) callPackage pi;
  };
in
{
  agent-browser = pkgs.callPackage ./agent-browser {
    agentBrowserSource = inputs.agent-browser-skill;
  };
  agent-slack = pkgs.callPackage ./agent-slack {
    agentSlackSource = inputs.agent-slack-skill;
  };
  claude-code = pkgs.callPackage ./claude-code {
    claudeCode = pkgs.claude-code;
    herdrPlugin = herdr.agent.plugin;
  };
  difit = pkgs.callPackage ./difit {
    difitSource = inputs.difit-src;
  };
  curl-fetch = pkgs.callPackage ./curl-fetch { };
  gh-api-get = pkgs.callPackage ./gh-api-get { };
  ghq-fetch-all = pkgs.callPackage ./ghq-fetch-all { };
  hunk = import ./hunk {
    inherit (pkgs) callPackage;
    hunkInput = inputs.hunk;
  };
  shellfirm = pkgs.callPackage ./shellfirm { };

  inherit
    aws
    codex
    hcom
    herdr
    pi
    ;
}
// lib.optionalAttrs hostPlatform.isLinux {
  drawio-headless = pkgs.callPackage ./drawio-headless { };
  wsl-set-ssh-auth-sock = pkgs.callPackage ./wsl-set-ssh-auth-sock { };
}
// lib.optionalAttrs hostPlatform.isDarwin {
  codex-app = pkgs.callPackage ./codex-app { };
}
