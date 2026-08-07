{
  den,
  flake-parts-lib,
  lib,
  ...
}:
let
  mergeValidationProducers = import ./_interface/validation-producers.nix { inherit lib; };
  validateNames = import ./_interface/validation-names.nix;
  ciCheck = import ../ci/_interface/check.nix { inherit lib; };
  checkProducer =
    {
      config,
      pkgs,
      ...
    }:
    let
      names = validateNames {
        apps = config.apps;
        validations = config.dotfiles.appValidations;
      };
      validationPaths = builtins.attrValues config.dotfiles.appValidations;
      gate =
        (pkgs.linkFarm "app-scripts" (
          lib.mapAttrsToList (name: path: { inherit name path; }) config.dotfiles.appValidations
        ))
        // {
          paths = validationPaths;
          inherit (names) validationNames;
        };
    in
    builtins.seq names (
      ciCheck.mkBuildProducer {
        owner = "app validation checks";
        entries.app-scripts = ciCheck.buildEntry (ciCheck.targets.bySystem {
          darwin = "configurations";
          linux = "repo-quality";
        }) gate;
      }
    );
in
{
  imports = [ ../ci/_interface/options.nix ];

  options.perSystem = flake-parts-lib.mkPerSystemOption {
    options.dotfiles.appValidations = lib.mkOption {
      type = lib.types.attrsOf lib.types.package;
      default = { };
      internal = true;
      description = "Validation derivations paired with every public app";
    };
  };

  config = {
    den.classes.appValidationGate = { };
    # The record keeps its nested function opaque while Den collects the quirk;
    # the consumer invokes it after flake-parts supplies per-system arguments.
    den.quirks.app-validations = {
      description = "Producers of system-parametric public app validation derivations";
    };

    den.policies.app-validation-gate-to-flake-parts = _: [
      (den.lib.policy.route {
        fromClass = "appValidationGate";
        intoClass = "flake-parts";
        path = [ "dotfiles" ];
        adaptArgs = { config, ... }: config.allModuleArgs;
      })
    ];

    den.aspects.app-validation-consumer.appValidationGate =
      {
        app-validations,
        pkgs,
        self',
        system,
        ...
      }:
      let
        validations = mergeValidationProducers {
          producers = app-validations;
          args = { inherit pkgs self' system; };
        };
      in
      {
        appValidations = validations;
      };

    den.aspects.app-validation-check.checks =
      { config, pkgs, ... }:
      (checkProducer { inherit config pkgs; }).checks;

    perSystem =
      {
        config,
        pkgs,
        ...
      }:
      {
        dotfiles.ci.buildRouteProducers = [
          {
            owner = "app validation checks";
            routes = (checkProducer { inherit config pkgs; }).routes;
          }
        ];
      };

    den.schema.flake-parts.includes = [
      den.policies.app-validation-gate-to-flake-parts
      den.aspects.app-validation-consumer
      den.aspects.app-validation-check
    ];
  };
}
