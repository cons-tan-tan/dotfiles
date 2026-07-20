{
  inputs,
  registry ? import ../packages,
}:
final: prev:
let
  localPackages = registry {
    inherit inputs;
    inherit (prev) lib;
    hostPlatform = prev.stdenv.hostPlatform;
    pkgs = final;
  };
in
{
  dotfilesPackages = localPackages;
}
