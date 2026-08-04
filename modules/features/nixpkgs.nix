{ inputs, ... }:
{
  perSystem =
    { system, ... }:
    {
      _module.args.pkgs = (import ../../nix/lib/mk-pkgs.nix { inherit inputs; }) system;
    };
}
