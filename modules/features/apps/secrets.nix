{ den, inputs, ... }:
let
  mkAspect = import ../../../nix/lib/apps/mk-common-den-aspect.nix {
    inherit inputs;
    username = "constantan";
  };
in
{
  den.aspects.secrets-app = mkAspect {
    group = "secrets";
    scriptNames = [ "apply-secrets" ];
  };

  den.schema.flake-parts.includes = [ den.aspects.secrets-app ];
}
