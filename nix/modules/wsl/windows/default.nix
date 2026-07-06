# Windows companion レイヤ: WSL ホストが Windows 側 (/mnt/c) に書き出す設定。
# wsl ホスト (nix/hosts/wsl.nix) からのみ import される前提なので、各モジュール
# はホスト種別ガード無しで home.activation を定義してよい。
{
  imports = [
    ./claude.nix
    ./git.nix
    ./gpg.nix
    ./powershell.nix
    ./static.nix
    ./winget.nix
  ];
}
