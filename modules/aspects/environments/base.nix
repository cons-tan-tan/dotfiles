{ den, ... }:
let
  homeManagerSettings = {
    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      # Preserve unmanaged files as backups instead of silently forcing them.
      backupFileExtension = "hm-backup";
    };
  };
in
{
  den.aspects.environments.base = {
    name = "dotfiles-environment-base";
    includes = [ den.batteries.flake-scope ];
  };

  den.aspects.environments.integrated-home-manager = {
    name = "dotfiles-integrated-home-manager";
    nixos = homeManagerSettings;
    darwin = homeManagerSettings;
  };
}
