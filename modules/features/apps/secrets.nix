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
  den.aspects.secrets-app = mkAspect { group = "secrets"; };

  den.schema.flake-parts.includes = [ den.aspects.secrets-app ];
}
