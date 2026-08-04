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
  den.aspects.update-pins-app = mkAspect { group = "update-pins"; };

  den.schema.flake-parts.includes = [ den.aspects.update-pins-app ];
}
