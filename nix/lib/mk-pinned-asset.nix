# nix/pins/*.json の assets map から現在の system の配布物を引く共有ロジック。
# 生成側の対称形は nix/apps/update-pins/src/targets.rs の refresh_assets。
{
  pin,
  system,
  label,
}:
{
  asset = pin.assets.${system} or (throw "${label}: unsupported system '${system}'");
  platforms = builtins.attrNames pin.assets;
}
