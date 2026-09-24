{ ... }:
let
  appsFor =
    { pkgs, ... }:
    import ./_interface/app-set.nix {
      inherit pkgs;
      repoRoot = ../../../..;
    };
in
{
  flake.modules.homeManager.security-secrets =
    { pkgs, ... }:
    {
      key = "modules/features/security/secrets/default.nix#homeManager.security-secrets";

      home.packages = [
        pkgs.sops
        pkgs.gopass
        pkgs.trufflehog
      ];
    };

  perSystem =
    { pkgs, ... }:
    let
      appSet = appsFor { inherit pkgs; };
    in
    {
      inherit (appSet) apps;
      dotfiles.appValidationSets = [ appSet.validationsByName ];
    };
}
