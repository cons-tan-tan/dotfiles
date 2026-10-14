{ lib, pkgs }:
{
  nativeBuildInputs = [
    pkgs.direnv
    pkgs.git
    pkgs.jq
  ];
  environment = {
    DIRENV_LOCAL_TEST_BIN = lib.getExe pkgs.direnv;
    DIRENVRC_TEST_FILE = ../_scripts/direnvrc.sh;
  };
  requiredEnvironment = [
    "DIRENV_LOCAL_TEST_BIN"
    "DIRENVRC_TEST_FILE"
  ];
}
