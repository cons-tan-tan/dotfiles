{
  den,
  ...
}:
let
  appsFor = { pkgs, ... }: import ./_lib/mk-app-set.nix { inherit pkgs; };
in
{
  den.aspects.lint = {
    apps = args: (appsFor args).apps;
    app-validations = [
      {
        produce = args: (appsFor args).validationsByName;
      }
    ];
  };

  den.schema.flake-parts.includes = [ den.aspects.lint ];
}
