{ ... }:
let
  appsFor = { pkgs, ... }: import ./_interface/update-apps.nix { inherit pkgs; };
in
{
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
