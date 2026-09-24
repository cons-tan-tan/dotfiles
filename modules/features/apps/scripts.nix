{ flake-parts-lib, lib, ... }:
let
  mergeValidations = import ./_interface/validation-producers.nix { inherit lib; };
  validateNames = import ./_interface/validation-names.nix;
  ciCheck = import ../ci/_interface/check.nix { inherit lib; };
in
{
  imports = [ ../ci/_interface/options.nix ];
  options.perSystem = flake-parts-lib.mkPerSystemOption {
    options.dotfiles = {
      appValidationSets = lib.mkOption {
        type = lib.types.listOf (lib.types.attrsOf lib.types.package);
        default = [ ];
        internal = true;
        description = "Validation derivations contributed alongside public apps.";
      };
      appValidations = lib.mkOption {
        type = lib.types.attrsOf lib.types.package;
        readOnly = true;
        internal = true;
        description = "Collected public app validations with unique names.";
      };
    };
  };
  config.perSystem =
    { config, pkgs, ... }:
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
      producer = builtins.seq names (
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
      dotfiles.appValidations = mergeValidations config.dotfiles.appValidationSets;
      checks = producer.checks;
      dotfiles.ci.buildRouteProducers = [ { inherit (producer) owner routes; } ];
    };
}
