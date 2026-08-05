{ inputs, ... }:
let
  inherit (import ./_interface) mkPkgs;
in
{
  perSystem =
    { system, ... }:
    {
      _module.args.pkgs = (mkPkgs { inherit inputs; }) system;
    };
}
