{ pkgs }:
let
  payload = import ../_interface/payload.nix;
  standard = (import ../_lib/mk-skill-source.nix { inherit pkgs; }) {
    name = "commit";
    provenance = "local";
    definition.root = payload.localSkillsRoot + "/commit";
  };
in
import ../_packages/commit-profiles {
  inherit pkgs standard;
  scopes = [ "github.com/team" ];
}
