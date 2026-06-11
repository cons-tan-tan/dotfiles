# standalone HM (mk-host.nix) と nix-darwin 内 HM (mk-darwin.nix) で共有する
# Home Manager モジュールリスト。構成パラメータは my.* options
# (nix/modules/options.nix) で配り、specialArgs は flake inputs のみにする。
{
  username,
  homedir,
  hostKind,
  hostFile,
  windowsUsername ? null,
  windowsHomedir ? null,
}:
[
  ../modules/options.nix
  hostFile
  {
    my = {
      inherit hostKind;
      dotfilesDir = "${homedir}/ghq/github.com/cons-tan-tan/dotfiles";
    }
    // (
      if hostKind == "wsl" then
        {
          windows = {
            username = windowsUsername;
            homedir = windowsHomedir;
          };
        }
      else
        { }
    );

    home = {
      inherit username;
      homeDirectory = homedir;
    };
  }
]
