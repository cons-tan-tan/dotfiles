{ den, ... }:
let
  appsFor =
    { pkgs, ... }:
    import ./_lib/mk-app-set.nix {
      inherit pkgs;
      repoRoot = ../../../..;
    };
in
{
  den.aspects.apply-secrets = {
    apps = args: (appsFor args).apps;
    app-validations = [
      {
        produce = args: (appsFor args).validationsByName;
      }
    ];
  };

  den.schema.flake-parts.includes = [ den.aspects.apply-secrets ];

  features.security-secrets = {
    name = "feature/security/secrets";
    homeManager =
      { pkgs, ... }:
      {
        home.packages = [
          pkgs.sops
          pkgs.gopass
          pkgs.trufflehog
        ];
      };
  };
}
