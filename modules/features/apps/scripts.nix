{
  den,
  flake-parts-lib,
  lib,
  ...
}:
let
  validateScriptEntries = import ../../../nix/lib/apps/validate-script-entries.nix { inherit lib; };
in
{
  options.perSystem = flake-parts-lib.mkPerSystemOption {
    options.dotfiles.appScripts = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      internal = true;
      description = "Validated app script derivations used by the shellcheck gate";
    };
  };

  config = {
    den.classes.appScriptGate = { };
    den.quirks.app-scripts = {
      description = "System-parametric app script derivations";
    };

    den.policies.app-script-gate-to-flake-parts = _: [
      (den.lib.policy.route {
        fromClass = "appScriptGate";
        intoClass = "flake-parts";
        path = [ "dotfiles" ];
        adaptArgs = { config, ... }: config.allModuleArgs;
      })
    ];

    den.aspects.app-script-consumer.appScriptGate =
      {
        app-scripts,
        pkgs,
        self',
        system,
        ...
      }:
      {
        appScripts = map (entry: entry.mkDerivation { inherit pkgs self' system; }) (
          validateScriptEntries app-scripts
        );
      };

    den.schema.flake-parts.includes = [
      den.policies.app-script-gate-to-flake-parts
      den.aspects.app-script-consumer
    ];
  };
}
