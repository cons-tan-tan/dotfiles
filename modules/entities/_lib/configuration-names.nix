# Linux/WSL の構成名を entity outputs と switch/build スクリプトで共有する。
{ username }:
let
  shortArch = {
    "x86_64-linux" = "x86_64";
    "aarch64-linux" = "aarch64";
  };
in
{
  forHost = { hostKind, system, ... }: "${username}@${hostKind}-${shortArch.${system}}";

  # x86_64 は通常利用する短い名前を維持し、aarch64 だけarchを明示する。
  forNixosWsl =
    { system, ... }:
    if system == "x86_64-linux" then "wsl" else "wsl-${shortArch.${system}}";
}
