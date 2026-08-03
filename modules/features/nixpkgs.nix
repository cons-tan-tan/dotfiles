{ inputs, ... }:
let
  mkPkgs = import ../../nix/lib/mk-pkgs.nix { inherit inputs; };
in
{
  perSystem =
    { system, ... }:
    {
      _module.args.pkgs = mkPkgs system;
    };
}
