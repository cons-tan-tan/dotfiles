{ pkgs }:
let
  appSet = import ../../apps/_interface/app-set.nix { lib = pkgs.lib; };
  core = pkgs.callPackage ../_packages/update-pins { };
  script = pkgs.writeShellApplication {
    name = "update-pins";
    runtimeInputs = [
      pkgs.cargo
      pkgs.curl
      pkgs.gitMinimal
      pkgs.nix
    ];
    text = ''
      exec ${pkgs.lib.getExe core} "$@"
    '';
  };
in
appSet.mkAppSet {
  entries.update-pins = {
    description = "Sync managed feature pins to the latest upstream state";
    inherit script;
  };
}
