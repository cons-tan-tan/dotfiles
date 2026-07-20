{
  hostPlatform,
  inputs,
  lib,
  pkgs,
}:
let
  hcom = import ./hcom {
    inherit (pkgs) callPackage;
    hcomSource = inputs.hcom-src;
  };
  herdr = import ./herdr {
    inherit (pkgs) callPackage;
  };
in
{
  agent-browser = pkgs.callPackage ./agent-browser {
    agentBrowserSource = inputs.agent-browser-skill;
  };
  agent-slack = pkgs.callPackage ./agent-slack {
    agentSlackSource = inputs.agent-slack-skill;
  };
  difit = pkgs.callPackage ./difit {
    difitSource = inputs.difit-src;
  };
  hunk = pkgs.callPackage ./hunk {
    hunkInput = inputs.hunk;
  };
  shellfirm = pkgs.callPackage ./shellfirm { };

  inherit hcom herdr;
}
// lib.optionalAttrs hostPlatform.isLinux {
  drawio-headless = pkgs.callPackage ./drawio-headless { };
}
// lib.optionalAttrs hostPlatform.isDarwin {
  codex-app = pkgs.callPackage ./codex-app { };
}
