{
  flake.modules.homeManager.editors-zed = {
    key = "modules/features/editors/zed.nix#homeManager.editors-zed";
    imports = [
      (
        { lib, pkgs, ... }:
        {
          home.packages = [
            # Avoid Zed remote falling back to its upstream glibc binary.
            pkgs.nodejs
          ]
          ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [ pkgs.brewCasks.zed ];
        }
      )
    ];
    dotfiles.cliTools = [
      {
        id = "zed";
        winget = {
          packageId = "ZedIndustries.Zed";
          description = "Zed";
        };
      }
    ];
  };
}
