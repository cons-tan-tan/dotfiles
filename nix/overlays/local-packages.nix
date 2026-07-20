{
  inputs,
  registry ? import ../packages,
}:
final: prev:
registry {
  inherit inputs;
  inherit (prev) lib;
  hostPlatform = prev.stdenv.hostPlatform;
  pkgs = final;
}
