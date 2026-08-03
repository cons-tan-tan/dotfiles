let
  cache = import ../../nix/lib/cache-settings.nix;
in
{
  flake-file.description = "constantan's home-manager configuration";

  flake-file.nixConfig = {
    extra-substituters = [
      "https://cache.nixos.org"
      cache.numtideSubstituter
      cache.nixCommunitySubstituter
    ];
    extra-trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      cache.numtideTrustedPublicKey
      cache.nixCommunityTrustedPublicKey
    ];
  };
}
