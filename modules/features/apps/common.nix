{ den, inputs, ... }:
let
  mkAspect = import ../../../nix/lib/apps/mk-common-den-aspect.nix {
    inherit inputs;
    username = "constantan";
  };
in
{
  den.aspects.common-apps = mkAspect {
    group = "maintenance";
    scriptNames = [
      "apply-nix-settings"
      "fmt"
      "update"
    ];
  };

  den.schema.flake-parts.includes = [ den.aspects.common-apps ];
}
