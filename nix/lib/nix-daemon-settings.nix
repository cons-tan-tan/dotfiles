{ username }:
let
  cache = import ./cache-settings.nix;
in
{
  # Let the daemon recover before a fast build can exhaust the filesystem;
  # the growth timer remains the normal, less urgent cleanup path.
  minFreeBytes = 32 * 1024 * 1024 * 1024;
  maxFreeBytes = 64 * 1024 * 1024 * 1024;

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
