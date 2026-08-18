{
  integratedWslAarch64System,
  integratedWslSystem,
  lib,
  standaloneWsl,
}:
let
  count =
    config:
    builtins.length (
      builtins.filter (
        package: lib.hasPrefix "wsl-dpapi" (lib.getName package)
      ) config.environment.systemPackages
    );
in
{
  actual = {
    integratedX86 = count integratedWslSystem;
    integratedAarch64 = count integratedWslAarch64System;
    standalone = lib.any (
      package: lib.hasPrefix "wsl-dpapi" (lib.getName package)
    ) standaloneWsl.home.packages;
  };
  expected = {
    integratedX86 = 1;
    integratedAarch64 = 1;
    standalone = false;
  };
}
