{ username }:
let
  cache = import ./cache-settings.nix;
in
{
  extraTrustedUsers = [
    username
  ];

  extraSubstituters = [
    cache.numtideSubstituter
  ];

  extraTrustedSubstituters = [
    cache.numtideSubstituter
  ];

  extraTrustedPublicKeys = [
    cache.numtideTrustedPublicKey
  ];
}
