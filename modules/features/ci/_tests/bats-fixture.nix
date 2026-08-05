{
  cacheSettings,
  pkgs,
}:
{
  nativeBuildInputs = [
    pkgs.jq
    pkgs.yq-go
  ];
  environment = {
    CACHE_NIX_COMMUNITY_SUBSTITUTER = cacheSettings.nixCommunitySubstituter;
    CACHE_NIX_COMMUNITY_TRUSTED_PUBLIC_KEY = cacheSettings.nixCommunityTrustedPublicKey;
    CACHE_NUMTIDE_SUBSTITUTER = cacheSettings.numtideSubstituter;
    CACHE_NUMTIDE_TRUSTED_PUBLIC_KEY = cacheSettings.numtideTrustedPublicKey;
  };
  requiredEnvironment = [
    "CACHE_NIX_COMMUNITY_SUBSTITUTER"
    "CACHE_NIX_COMMUNITY_TRUSTED_PUBLIC_KEY"
    "CACHE_NUMTIDE_SUBSTITUTER"
    "CACHE_NUMTIDE_TRUSTED_PUBLIC_KEY"
  ];
}
