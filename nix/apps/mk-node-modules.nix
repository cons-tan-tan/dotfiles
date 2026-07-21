# importNpmLock ベースの node_modules 構築。lint CLI (mk-node-lint-app.nix)
# と pptx の node wrapper が共有する。
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
