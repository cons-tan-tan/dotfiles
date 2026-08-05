# importNpmLock ベースの node_modules 構築。app owner が lockfile から
# reproducible な Node runtime を組み立てるための共通 projection primitive。
{ pkgs }:
{
  name,
  nodeDir,
}:
let
  nodePackage = pkgs.lib.importJSON (nodeDir + "/package.json");
in
pkgs.importNpmLock.buildNodeModules {
  package = nodePackage;
  packageLock = pkgs.lib.importJSON (nodeDir + "/package-lock.json");
  inherit (pkgs) nodejs;
  derivationArgs = {
    pname = "${name}-node-modules";
    version = nodePackage.version;
  };
}
