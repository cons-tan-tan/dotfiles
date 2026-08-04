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
    ./agent-guidance
    (withInputs ./agent-skills)
    ./hcom.nix
    ./hcom-package.nix
    (withInputs ./programs)
  ];
}
