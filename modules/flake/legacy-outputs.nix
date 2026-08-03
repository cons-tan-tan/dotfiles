{
  config,
  inputs,
  lib,
  withSystem,
  ...
}:
{
  flake = import ../_legacy/outputs.nix {
    inherit inputs;
    pkgsFor = lib.genAttrs config.systems (system: withSystem system ({ pkgs, ... }: pkgs));
  };
}
