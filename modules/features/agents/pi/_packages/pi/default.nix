{
  callPackage,
  pi,
}:
{
  packageManager = callPackage ./package-manager.nix { };

  mkWrappedPackage =
    { packageDir }:
    callPackage ./wrapped-package.nix {
      inherit packageDir pi;
    };
}
