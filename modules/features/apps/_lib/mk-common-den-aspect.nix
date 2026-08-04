{
  den,
  inputs,
  lib,
}:
{ group }:
let
  appsFor =
    {
      pkgs,
      self',
      ...
    }:
    let
      system = pkgs.stdenv.hostPlatform.system;
      context = (import ../../../entities/_lib/configuration-targets.nix { inherit lib; }) {
        inherit den system;
      };
      mkCommonApps = import ../../../../nix/lib/apps/mk-common-apps.nix {
        inherit inputs;
        username = context.username;
      };
    in
    mkCommonApps {
      inherit pkgs;
      treefmtWrapper = self'.formatter;
    };
  groupFor = args: (appsFor args).groups.${group};
in
{
  apps = args: (groupFor args).apps;

  app-validations = [
    {
      produce = args: (groupFor args).validationsByName;
    }
  ];
}
