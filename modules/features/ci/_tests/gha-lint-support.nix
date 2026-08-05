{ lib, pkgs }:
let
  sources = import ../_packages/gha-lint/sources.nix {
    inherit lib;
    inherit (pkgs) fetchurl;
  };
in
{
  inherit (sources) fixtures schemas;
}
