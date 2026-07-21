# flake.nix の nixConfig は直接の attrset を要求するため、対象リスト全体が
# cache-settings.nix と乖離していないことを通常の Nix import で検証する。
let
  cache = import ./cache-settings.nix;
  flakeConfig = (import ../../flake.nix).nixConfig;
in
{
  testFlakeNixConfigContainsNumtideSubstituter = {
    expr = flakeConfig.extra-substituters;
    expected = [
      "https://cache.nixos.org"
      cache.numtideSubstituter
    ];
  };

  testFlakeNixConfigContainsNumtideKey = {
    expr = flakeConfig.extra-trusted-public-keys;
    expected = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      cache.numtideTrustedPublicKey
    ];
  };
}
