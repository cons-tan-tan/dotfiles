{
  flake-parts-lib,
  lib,
  ...
}:
{
  options.perSystem = flake-parts-lib.mkPerSystemOption {
    options.dotfiles.ci = {
      evaluationCompleteCheckProducers = lib.mkOption {
        type = lib.types.listOf (
          lib.types.submodule {
            options = {
              owner = lib.mkOption { type = lib.types.nonEmptyStr; };
              checks = lib.mkOption { type = lib.types.lazyAttrsOf lib.types.raw; };
            };
          }
        );
        default = [ ];
        internal = true;
        description = "Lazily indexed checks whose assertions finish before derivation build";
      };
      buildRouteProducers = lib.mkOption {
        type = lib.types.listOf (
          lib.types.submodule {
            options = {
              owner = lib.mkOption { type = lib.types.nonEmptyStr; };
              routes = lib.mkOption { type = lib.types.lazyAttrsOf lib.types.raw; };
            };
          }
        );
        default = [ ];
        internal = true;
        description = "Lazily indexed Hestia routes for build checks";
      };
    };
  };
}
