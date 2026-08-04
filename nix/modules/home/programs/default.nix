{ inputs, ... }:
let
  withInputs =
    path:
    {
      config,
      lib,
      pkgs,
      ...
    }:
    import path {
      inherit
        config
        inputs
        lib
        pkgs
        ;
    };
in
{
  imports = [
    (withInputs ./claude.nix)
    ./codex.nix
    ./herdr.nix
    (withInputs ./hunk.nix)
    ./nh.nix
    ./opencode.nix
    ./pi.nix
  ];
}
