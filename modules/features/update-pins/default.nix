{ den, ... }:
let
  updatePins = import ./_interface;
  appsFor = { pkgs, ... }: updatePins.mkAppSet { inherit pkgs; };
in
{
  den.aspects.update-pins = {
    apps = args: (appsFor args).apps;
    app-validations = [
      {
        produce = args: (appsFor args).validationsByName;
      }
    ];
  };

  den.schema.flake-parts.includes = [ den.aspects.update-pins ];
}
