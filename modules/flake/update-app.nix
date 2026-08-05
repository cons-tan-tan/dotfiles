{ den, ... }:
let
  appsFor = { pkgs, ... }: import ./_lib/mk-update-app-set.nix { inherit pkgs; };
in
{
  den.aspects.flake-update = {
    apps = args: (appsFor args).apps;
    app-validations = [
      {
        produce = args: (appsFor args).validationsByName;
      }
    ];
  };

  den.schema.flake-parts.includes = [ den.aspects.flake-update ];
}
