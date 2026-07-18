_final: prev:
let
  rustPlatform = prev.rustPlatform // {
    buildRustPackage =
      args:
      prev.rustPlatform.buildRustPackage (
        if builtins.isFunction args then
          finalAttrs:
          (args finalAttrs)
          // {
            auditable = false;
          }
        else
          args
          // {
            auditable = false;
          }
      );
  };
in
{
  # Darwin's cctools ld crashes while linking cargo-auditable's audit object
  # into watchexec. Keep the workaround scoped to this package and platform.
  watchexec = prev.watchexec.override {
    inherit rustPlatform;
  };
}
