{ inputs, username }:
{
  group,
  scriptNames ? [ ],
}:
let
  mkCommonApps = import ./mk-common-apps.nix { inherit inputs username; };
  appsFor =
    { pkgs, self', ... }:
    mkCommonApps {
      inherit pkgs;
      treefmtWrapper = self'.formatter;
    };
  groupFor = args: (appsFor args).groups.${group};
in
{
  apps = args: (groupFor args).apps;

  app-scripts = map (name: {
    inherit name;
    mkDerivation = args: (groupFor args).scriptsByName.${name};
  }) scriptNames;
}
