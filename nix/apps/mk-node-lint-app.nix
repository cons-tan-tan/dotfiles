# importNpmLock ベースの node 製 lint CLI app の共通部品。
# node/ ディレクトリの lockfile から node_modules を構築し、NODE_PATH を通して
# node_modules 配下の entry スクリプトを exec するシェル断片を提供する。
# CLI (usage / mode 分岐) は各 app 側に残す。
{ pkgs }:
{
  name,
  nodeDir,
}:
let
  nodePackage = pkgs.lib.importJSON (nodeDir + "/package.json");

  nodeModules = pkgs.importNpmLock.buildNodeModules {
    package = nodePackage;
    packageLock = pkgs.lib.importJSON (nodeDir + "/package-lock.json");
    inherit (pkgs) nodejs;
    derivationArgs = {
      pname = "${name}-node-modules";
      version = nodePackage.version;
    };
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
