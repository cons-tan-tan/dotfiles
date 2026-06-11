# gpg-agent の共有定数。現ホスト用 (modules/home/programs/gpg.nix) と
# Windows companion 用 (modules/wsl/windows/gpg.nix) で共有する。
{
  cacheTtl = 43200;
  sshKeygrips = [
    "60DE257CE1919B3D6DCF4E6E239CD1FFE63B45FD"
  ];
}
