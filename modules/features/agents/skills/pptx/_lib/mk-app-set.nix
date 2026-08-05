{
  inputs,
  pkgs,
}:
let
  appSet = import ../../../../apps/_interface/app-set.nix { lib = pkgs.lib; };
  pptx = import ../_packages/pptx {
    inherit pkgs;
    inherit (inputs)
      anthropic-skills
      pyproject-build-systems
      pyproject-nix
      uv2nix
      ;
    mkNodeModules = import ../../../../apps/_interface/node-modules.nix { inherit pkgs; };
  };
in
appSet.mkAppSet { entries = { inherit pptx; }; }
