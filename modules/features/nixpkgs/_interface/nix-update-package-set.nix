{
  system ? builtins.currentSystem,
  ...
}:
let
  repoRoot = ../../../..;
  flake = builtins.getAttr "getFlake" builtins (toString repoRoot);
  inherit (import ./.) mkPkgs;
in
(mkPkgs { inputs = flake.inputs; } system).dotfilesPackages
