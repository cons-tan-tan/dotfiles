{ den, inputs, ... }:
let
  mkAspect = import ../../../nix/lib/apps/mk-common-den-aspect.nix {
    inherit inputs;
    username = "constantan";
  };
in
{
  den.aspects.update-pins-app = mkAspect {
    group = "update-pins";
    scriptNames = [ "update-pins" ];
  };

  den.schema.flake-parts.includes = [ den.aspects.update-pins-app ];
}
