{
  pkgs,
  updateScripts ? import ./update-scripts.nix { inherit pkgs; },
}:
let
  appSet = import ../../apps/_interface/app-set.nix { lib = pkgs.lib; };
  registryFile = pkgs.writeText "update-pins-registry.json" (builtins.toJSON updateScripts);
  script = pkgs.writeShellApplication {
    name = "update-pins";
    runtimeInputs = [
      pkgs.gitMinimal
      pkgs.jq
    ];
    runtimeEnv.UPDATE_PINS_REGISTRY = registryFile;
    text = builtins.readFile ../_scripts/update-pins.sh;
  };
in
appSet.mkAppSet {
  entries.update-pins = {
    description = "Run package-owned update scripts";
    inherit script;
  };
}
