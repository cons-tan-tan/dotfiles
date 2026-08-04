{
  lib,
  pkgs,
  subjects,
}:
let
  curlFetch = pkgs.dotfilesPackages.curl-fetch;
  ghApiGet = pkgs.dotfilesPackages.gh-api-get;
in
{
  nativeBuildInputs = [
    ghApiGet
    subjects.safeFetch.core
    curlFetch
  ];
  environment = {
    CURL_FETCH_PUBLIC_BIN = lib.getExe curlFetch;
    CURL_FETCH_TEST_BIN = "${subjects.safeFetch.core}/bin/curl-fetch";
    GH_API_GET_EXTENSION_ROOT = ghApiGet;
    GH_API_GET_PUBLIC_BIN = lib.getExe ghApiGet;
    GH_API_GET_TEST_BIN = "${subjects.safeFetch.core}/bin/gh-api-get";
  };
  requiredEnvironment = [
    "CURL_FETCH_PUBLIC_BIN"
    "CURL_FETCH_TEST_BIN"
    "GH_API_GET_EXTENSION_ROOT"
    "GH_API_GET_PUBLIC_BIN"
    "GH_API_GET_TEST_BIN"
  ];
}
