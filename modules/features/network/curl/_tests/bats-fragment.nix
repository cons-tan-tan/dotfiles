{
  lib,
  pkgs,
}:
let
  curlFetch = pkgs.dotfilesPackages.curl-fetch;
in
{
  group = "safeFetch";
  fixture = {
    nativeBuildInputs = [ curlFetch ];
    environment = {
      CURL_FETCH_PUBLIC_BIN = lib.getExe curlFetch;
    };
    requiredEnvironment = [ "CURL_FETCH_PUBLIC_BIN" ];
  };
  shard = {
    testFiles = [ "modules/features/network/curl/_tests/curl-fetch.bats" ];
    sourceFiles = [ ];
  };
}
