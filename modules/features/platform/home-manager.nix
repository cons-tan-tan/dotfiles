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
  flake.modules.darwin.platform-integrated-home-manager = {
    key = "modules/features/platform/home-manager.nix#darwin.platform-integrated-home-manager";
    imports = [ settings ];
  };

  flake.modules.nixos.platform-integrated-home-manager = {
    key = "modules/features/platform/home-manager.nix#nixos.platform-integrated-home-manager";
    imports = [ settings ];
  };
}
