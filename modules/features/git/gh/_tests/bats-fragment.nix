{
  lib,
  pkgs,
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
    };
    requiredEnvironment = [
      "GH_API_GET_EXTENSION_ROOT"
      "GH_API_GET_PUBLIC_BIN"
    ];
  };
  shard = {
    testFiles = [ "modules/features/git/gh/_tests/gh-api-get.bats" ];
    sourceFiles = [ ];
  };
}
