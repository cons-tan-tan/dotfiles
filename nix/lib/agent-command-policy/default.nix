# 共通ruleを型検証し、各consumer向けの公開APIを返す。
{ lib }:
let
  evaluated = lib.evalModules {
    modules = [
      ./options.nix
      ./rules.nix
    ];
  };
in
import ./compiler.nix {
  inherit lib;
  rules = evaluated.config.agentCommandPolicy.rules;
}
