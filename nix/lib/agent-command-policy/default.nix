# 共通policyを型検証し、各consumer向けの公開APIを返す。
{ lib }:
let
  evaluated = lib.evalModules {
    modules = [
      ./options.nix
      ./rules.nix
    ];
  };
  policy = evaluated.config.agentCommandPolicy;
in
import ./compiler.nix {
  inherit lib;
  inherit (policy) argv semantic shellfirm;
}
