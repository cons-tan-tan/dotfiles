let
  fixturePin.assets = {
    aarch64-linux = {
      name = "fixture-aarch64";
      hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    };
    x86_64-linux = {
      name = "fixture-x86_64";
      hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    };
  };
  fixture = import ../_lib/mk-pinned-asset.nix {
    pin = fixturePin;
    system = "x86_64-linux";
    label = "fixture";
  };
in
{
  testSelectsCurrentSystemAsset = {
    expr = fixture.asset.name;
    expected = "fixture-x86_64";
  };

  testDerivesPlatformsFromAssets = {
    expr = fixture.platforms;
    expected = [
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}
