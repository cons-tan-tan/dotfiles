{ pkgs, ... }:
let
  # read-only HTTP(S) curl ラッパー。フラグ検査ロジックは bats でテストするため
  # 素の bash ファイル (curl-fetch.sh) に分離している。
  # writeShellApplication なのでビルド時に shellcheck がかかる。
  curl-fetch = pkgs.writeShellApplication {
    name = "curl-fetch";
    runtimeInputs = [ pkgs.curl ];
    text = builtins.readFile ./curl-fetch.sh;
  };
in
{
  home.packages = [
    pkgs.curl
    curl-fetch
  ];
}
