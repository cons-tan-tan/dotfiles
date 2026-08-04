{
  lib,
  pkgs,
  subjects,
}:
{
  nativeBuildInputs = [
    pkgs.git
    pkgs.gnutar
    pkgs.gzip
    pkgs.jq
    pkgs.zip
    subjects.updatePinsCore
  ];
  environment.UPDATE_PINS_TEST_BIN = lib.getExe subjects.updatePinsCore;
  requiredEnvironment = [ "UPDATE_PINS_TEST_BIN" ];
}
