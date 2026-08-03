{ den, inputs, ... }:
let
  mkAspect = import ../../../nix/lib/apps/mk-common-den-aspect.nix {
    inherit inputs;
    username = "constantan";
  };
in
{
  den.aspects.lint-apps = mkAspect { group = "lint"; };

  den.schema.flake-parts.includes = [ den.aspects.lint-apps ];
}
