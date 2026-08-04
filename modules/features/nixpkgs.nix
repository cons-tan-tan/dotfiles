{
  den,
  flake-parts-lib,
  inputs,
  lib,
  ...
}:
let
  validateUnfreePackageNames = import ./_lib/validate-flake-unfree-packages.nix { inherit lib; };
in
{
  options.perSystem = flake-parts-lib.mkPerSystemOption {
    options.dotfiles.unfreePackageNames = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      internal = true;
      description = "Validated unfree package names used by flake outputs";
    };
  };

  config = {
    den.classes.flakeUnfreeGate = { };
    den.quirks.flake-unfree-packages = {
      description = "Unfree package names required by flake output features";
    };

    den.policies.flake-unfree-gate-to-flake-parts = _: [
      (den.lib.policy.route {
        fromClass = "flakeUnfreeGate";
        intoClass = "flake-parts";
        path = [ "dotfiles" ];
        adaptArgs = { config, ... }: config.allModuleArgs;
      })
    ];

    den.aspects.flake-unfree-consumer.flakeUnfreeGate =
      { flake-unfree-packages, ... }:
      {
        unfreePackageNames = validateUnfreePackageNames flake-unfree-packages;
      };

    den.schema.flake-parts.includes = [
      den.policies.flake-unfree-gate-to-flake-parts
      den.aspects.flake-unfree-consumer
    ];

    perSystem =
      { config, system, ... }:
      {
        _module.args.pkgs =
          (import ../../nix/lib/mk-pkgs.nix {
            inherit inputs;
            inherit (config.dotfiles) unfreePackageNames;
          })
            system;
      };
  };
}
