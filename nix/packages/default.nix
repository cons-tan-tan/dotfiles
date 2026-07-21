# dotfilesPackages の登録簿。
#
# 登録の形は 3 種で、契約は package-families.test.nix / namespace.test.nix が固定する:
#   - 葉 package: 成果物が 1 つの CLI は callPackage で derivation を直接登録する
#     (例: curl-fetch, difit — difit は skill 用の flake input を別途持つが
#     成果物は CLI 1 つなので family にしない)。
#   - 直接 derivation 型 family: 複数の成果物を持ち、生成に必要な値が登録時に
#     すべて揃うものは { package, ... } を持つ (例: hcom, herdr, hunk, claude-code)。
#   - builder 型 family: wrapper の生成に消費側しか知らない値が要るものは
#     { mk*, ... } の builder を持つ (例: codex の herdrSkillPath,
#     pi の packageDir, aws の loginConfigFile)。
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
  claude-code = import ./claude-code {
    inherit (pkgs) callPackage;
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
