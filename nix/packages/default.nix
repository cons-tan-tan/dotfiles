{
  hostPlatform,
  inputs,
  lib,
  pkgs,
}:
let
  hcomPackages = pkgs.callPackage ./hcom {
    hcomSource = inputs.hcom-src;
  };
  herdrPackages = pkgs.callPackage ./herdr { };
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

  inherit (hcomPackages)
    hcom
    hcom-claude-hooks
    hcom-codex-hooks
    ;

  inherit (herdrPackages)
    herdr
    herdr-agent-plugin
    herdr-agent-skill
    herdr-claude-integration
    herdr-codex-integration
    herdr-codex-marketplace
    herdr-opencode-integration
    herdr-pi-integration
    ;
}
// lib.optionalAttrs hostPlatform.isLinux {
  drawio-headless = pkgs.callPackage ./drawio-headless { };
}
// lib.optionalAttrs hostPlatform.isDarwin {
  codex-app = pkgs.callPackage ./codex-app { };
}
