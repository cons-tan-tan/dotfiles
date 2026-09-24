{
  ...
}:
let
  appsFor = { pkgs, ... }: import ./_interface/app-set.nix { inherit pkgs; };
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
