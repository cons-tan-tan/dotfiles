{
  lib,
  pkgs,
  subjects,
}:
let
  curlFetch = pkgs.dotfilesPackages.curl-fetch;
in
{
  fixture = {
    nativeBuildInputs = [
      subjects.safeFetch.core
      curlFetch
    ];
    environment = {
      CURL_FETCH_PUBLIC_BIN = lib.getExe curlFetch;
      CURL_FETCH_TEST_BIN = "${subjects.safeFetch.core}/bin/curl-fetch";
    };
    requiredEnvironment = [
      "CURL_FETCH_PUBLIC_BIN"
      "CURL_FETCH_TEST_BIN"
    ];
  };
  shard = {
    testFiles = [ "modules/features/network/curl/_tests/curl-fetch.bats" ];
    sourceFiles = [ ];
  };
}
