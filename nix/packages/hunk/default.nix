{
  callPackage,
  hunkInput,
}:
let
  package = callPackage ./package.nix {
    inherit hunkInput;
  };
in
{
  inherit package;
  wslRuntime = callPackage ./wsl-runtime.nix {
    inherit package;
  };
}
