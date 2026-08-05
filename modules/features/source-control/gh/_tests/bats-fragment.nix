{
  lib,
  pkgs,
  subjects,
}:
let
  ghApiGet = pkgs.dotfilesPackages.gh-api-get;
in
{
  group = "safeFetch";
  fixture = {
    nativeBuildInputs = [ ghApiGet ];
    environment = {
      GH_API_GET_EXTENSION_ROOT = ghApiGet;
      GH_API_GET_PUBLIC_BIN = lib.getExe ghApiGet;
      GH_API_GET_TEST_BIN = "${subjects.safeFetch.core}/bin/gh-api-get";
    };
    requiredEnvironment = [
      "GH_API_GET_EXTENSION_ROOT"
      "GH_API_GET_PUBLIC_BIN"
      "GH_API_GET_TEST_BIN"
    ];
  };
  shard = {
    testFiles = [ "modules/features/source-control/gh/_tests/gh-api-get.bats" ];
    sourceFiles = [ ];
  };
}
