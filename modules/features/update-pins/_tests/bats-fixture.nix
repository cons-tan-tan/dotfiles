{
  lib,
  pkgs,
  ...
}:
let
  alpha = pkgs.writeShellApplication {
    name = "update-alpha-test";
    text = ''
      printf 'alpha:%s\n' "$*" >>"''${UPDATE_PINS_TEST_LOG:?}"
      if [[ ''${UPDATE_PINS_TEST_TOUCH:-} == alpha ]]; then
        printf 'changed\n' >managed-pin
      fi
    '';
  };
  beta = pkgs.writeShellApplication {
    name = "update-beta-test";
    text = ''
      printf 'beta:%s\n' "$*" >>"''${UPDATE_PINS_TEST_LOG:?}"
      if [[ ''${UPDATE_PINS_TEST_FAIL:-} == beta ]]; then
        exit 42
      fi
    '';
  };
  runner =
    (import ../_interface/app-set.nix {
      inherit pkgs;
      updateScripts = {
        alpha = {
          command = [
            (lib.getExe alpha)
            "fixed"
          ];
          description = "Update alpha fixture";
        };
        beta = {
          command = [ (lib.getExe beta) ];
          description = "Update beta fixture";
        };
      };
    }).validationsByName.update-pins;
in
{
  nativeBuildInputs = [
    pkgs.git
    runner
  ];
  environment.UPDATE_PINS_TEST_BIN = lib.getExe runner;
  requiredEnvironment = [ "UPDATE_PINS_TEST_BIN" ];
}
