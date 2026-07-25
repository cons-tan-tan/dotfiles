{
  callPackage,
  hunkInput,
  stdenv,
}:
let
  package = hunkInput.packages.${stdenv.hostPlatform.system}.default;
in
{
  inherit package;
  wslRuntime = callPackage ./wsl-runtime.nix {
    inherit package;
  };
}
