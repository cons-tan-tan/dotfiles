{ ... }:
let
  updatePins = import ./_interface;
  appsFor = { pkgs, ... }: updatePins.mkAppSet { inherit pkgs; };
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
