# importNpmLock ベースの node 製 lint CLI data planeの共通部品。
# node/ ディレクトリの lockfile から node_modules を構築し、NODE_PATH を通して
# node_modules 配下の entry スクリプトを exec するシェル断片を提供する。
# CLI control plane (usage / mode 分岐) は各appのrunner factoryが所有する。
{ pkgs }:
{
  name,
  nodeDir,
}:
let
  nodeModules = import ../../apps/_interface/node-modules.nix { inherit pkgs; } {
    inherit name nodeDir;
  };
in
{
  inherit nodeModules;

  # entry: node_modules 配下の実行スクリプト相対パス
  mkExec = entry: ''
    export NODE_PATH="${nodeModules}/node_modules''${NODE_PATH:+:$NODE_PATH}"
    exec ${pkgs.nodejs}/bin/node \
      "${nodeModules}/node_modules/${entry}"'';
}
