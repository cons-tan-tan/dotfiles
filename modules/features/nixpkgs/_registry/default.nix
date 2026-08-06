# Build feature-owned packages here so the overlay can reject namespace
# collisions before exposing the single dotfilesPackages registry.
{
  hostPlatform,
  inputs,
  lib,
  pkgs,
}:
let
  mkPinnedAsset = import ../_lib/mk-pinned-asset.nix;
  agentPackageSources = import ../../agents/_interface/package-sources.nix;
  ciPackageSources = import ../../ci/_interface/package-sources.nix;
  cloudPackageSources = import ../../cloud/_interface/package-sources.nix;
  drawioPackageSources = import ../../drawio/_interface/package-sources.nix;
  networkPackageSources = import ../../network/_interface/package-sources.nix;
  platformPackageSources = import ../../platform/_interface/package-sources.nix;
  securityPackageSources = import ../../security/_interface/package-sources.nix;
  sourceControlPackageSources = import ../../source-control/_interface/package-sources.nix;
  agentConfigHelper = pkgs.callPackage agentPackageSources.configHelper { };
  safeFetch = pkgs.callPackage networkPackageSources.safeFetch { };
  ghApiGet = pkgs.callPackage sourceControlPackageSources.ghApiGet {
    safeFetchCore = safeFetch.core;
  };
  aws = import cloudPackageSources.aws {
    inherit (pkgs) callPackage;
  };
  hcom = import agentPackageSources.hcom {
    inherit (pkgs) callPackage;
    inherit agentConfigHelper ghApiGet mkPinnedAsset;
    hcomSource = inputs.hcom-src;
  };
  codex = import agentPackageSources.codex {
    inherit (pkgs) callPackage;
    inherit (pkgs) codex;
  };
  herdr = import agentPackageSources.herdr {
    inherit (pkgs) callPackage;
    inherit ghApiGet mkPinnedAsset;
  };
  pi = import agentPackageSources.pi {
    inherit (pkgs) callPackage pi;
  };
in
{
  agent-browser = pkgs.callPackage agentPackageSources.browser {
    agentBrowserSource = inputs.agent-browser-skill;
    inherit ghApiGet mkPinnedAsset;
  };
  agent-command-guard = pkgs.callPackage agentPackageSources.commandGuard { };
  agent-slack = pkgs.callPackage agentPackageSources.slack {
    agentSlackSource = inputs.agent-slack-skill;
    inherit ghApiGet mkPinnedAsset;
  };
  claude-code = import agentPackageSources.claudeCode {
    inherit (pkgs) callPackage;
    claudeCode = pkgs.claude-code;
    herdrPlugin = herdr.agent.plugin;
  };
  difit = pkgs.callPackage agentPackageSources.difit {
    difitSource = inputs.difit-src;
  };
  curl-fetch = safeFetch.curlFetch;
  gh-api-get = ghApiGet;
  gha-lint = pkgs.callPackage ciPackageSources.ghaLint {
    bun2nix = inputs.bun2nix.packages.${hostPlatform.system}.default;
  };
  ghq-fetch-all = pkgs.callPackage sourceControlPackageSources.ghqFetchAll { };
  hunk = import agentPackageSources.hunk {
    inherit (pkgs) callPackage stdenv;
    hunkInput = inputs.hunk;
  };
  shellfirm = pkgs.callPackage agentPackageSources.shellfirm { inherit ghApiGet; };

  inherit
    aws
    codex
    hcom
    herdr
    pi
    ;
}
// lib.optionalAttrs hostPlatform.isLinux {
  ci-matrix-planner = pkgs.callPackage ciPackageSources.matrixPlanner { };
  drawio-headless = pkgs.callPackage drawioPackageSources.headless { };
  wsl-open = pkgs.callPackage platformPackageSources.wslOpen { };
  wsl-set-ssh-auth-sock = pkgs.callPackage securityPackageSources.wslSetSshAuthSock { };
}
// lib.optionalAttrs hostPlatform.isDarwin {
  codex-app = pkgs.callPackage agentPackageSources.codexApp { };
  sleepctl = pkgs.callPackage platformPackageSources.sleepctl { };
}
