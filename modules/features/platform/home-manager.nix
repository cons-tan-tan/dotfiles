let
  settings = {
    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      # Preserve unmanaged files as backups instead of silently forcing them.
      backupFileExtension = "hm-backup";
    };
  };
in
{
  features.platform-integrated-home-manager = {
    name = "feature/platform/integrated-home-manager";
    nixos = settings;
    darwin = settings;
  };
}
