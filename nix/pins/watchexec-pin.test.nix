let
  pin = builtins.fromJSON (builtins.readFile ./watchexec.json);
in
{
  testDarwinSystemsArePinned = {
    expr = builtins.attrNames pin.assets;
    expected = [
      "aarch64-darwin"
      "x86_64-darwin"
    ];
  };

  testDarwinTargetsAreDistinct = {
    expr = map (asset: asset.target) (builtins.attrValues pin.assets);
    expected = [
      "aarch64-apple-darwin"
      "x86_64-apple-darwin"
    ];
  };
}
