{
  callPackage,
  hunkInput,
  lib,
  stdenv,
}:
let
  bun2nix = hunkInput.inputs.bun2nix;
  bun2nixInputs = bun2nix.inputs;
  buildPackageModule = "${bun2nix}/nix/fetch-bun-deps/build-package.nix";

  # bun2nix 2.0.8 closes over this helper through self', so consumers cannot
  # override its source. Reuse the upstream module while substituting the
  # fresh-store-safe helper package below.
  patchedBuildPackage =
    moduleArgs:
    let
      upstream = import buildPackageModule moduleArgs;
    in
    upstream
    // {
      config = upstream.config // {
        perSystem =
          perSystemArgs@{
            config,
            pkgs,
            self',
            ...
          }:
          let
            cacheEntryCreator = config.packages.cacheEntryCreator.overrideAttrs {
              # A store subpath used as src is not registered on fresh runners.
              # Unpack the complete flake input and select the source directory.
              src = bun2nix;
              sourceRoot = "source/programs/cache-entry-creator";
              postConfigure = ''
                ln -s ${
                  pkgs.callPackage "${bun2nix}/programs/cache-entry-creator/deps.nix" { }
                } "$ZIG_GLOBAL_CACHE_DIR/p"
              '';
            };
          in
          upstream.config.perSystem (
            perSystemArgs
            // {
              inherit config pkgs;
              self' = self' // {
                packages = self'.packages // {
                  inherit cacheEntryCreator;
                };
              };
            }
          );
      };
    };

  patchedBun2nix =
    bun2nixInputs.flake-parts.lib.mkFlake
      {
        inputs = bun2nixInputs // {
          # Preserve the input's source identity while replacing its evaluated
          # outputs with the patched module graph.
          self = bun2nix // patchedBun2nix;
        };
      }
      {
        imports = [
          (
            (bun2nixInputs.import-tree.filterNot (
              path: lib.hasSuffix "/fetch-bun-deps/build-package.nix" (toString path)
            ))
            "${bun2nix}/nix"
          )
          patchedBuildPackage
        ];
      };
in
callPackage "${hunkInput}/nix/package.nix" {
  bun2nix = patchedBun2nix.packages.${stdenv.hostPlatform.system}.default;
}
