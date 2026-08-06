# package owner が持つ pin の assets map から現在の system の配布物を引く共有ロジック。
# 更新側は各 package の passthru.updateScript が所有する。
{
  pin,
  system,
  label,
}:
{
  asset = pin.assets.${system} or (throw "${label}: unsupported system '${system}'");
  platforms = builtins.attrNames pin.assets;
}
