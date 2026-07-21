# Linux/WSL の homeConfigurations 名 ("user@kind-arch") の単一ソース。
# flake.nix (構成の属性名) と mk-linux-apps.nix (switch/build スクリプトへ
# 渡す候補名) の双方がここから組み立てる。
{ username }:
let
  shortArch = {
    "x86_64-linux" = "x86_64";
    "aarch64-linux" = "aarch64";
  };
in
{
  inherit shortArch;
  forHost = { hostKind, system, ... }: "${username}@${hostKind}-${shortArch.${system}}";
}
