{
  den,
  inputs,
  lib,
  ...
}:
let
  mkAspect = import ./_lib/mk-common-den-aspect.nix {
    inherit den inputs lib;
  };
in
{
  den.aspects.common-apps = mkAspect { group = "maintenance"; };

  den.schema.flake-parts.includes = [ den.aspects.common-apps ];
}
