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
    cache.nixCommunitySubstituter
  ];

  extraTrustedSubstituters = [
    cache.numtideSubstituter
    cache.nixCommunitySubstituter
  ];

  extraTrustedPublicKeys = [
    cache.numtideTrustedPublicKey
    cache.nixCommunityTrustedPublicKey
  ];
}
