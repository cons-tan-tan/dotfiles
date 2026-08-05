{ pkgs }:
let
  appSet = import ../../apps/_interface/app-set.nix { lib = pkgs.lib; };
  markdownlint = import ../_packages/markdownlint { inherit pkgs; };
  textlint = import ../_packages/textlint { inherit pkgs; };
in
appSet.mkAppSet {
  entries = { inherit markdownlint textlint; };
}
