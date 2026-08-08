{
  features.editors-zed = {
    name = "feature/editors/zed";
    cli-tools = [
      {
        id = "zed";
        winget = {
          packageId = "ZedIndustries.Zed";
          description = "Zed";
        };
      }
    ];
    homeManager =
      { lib, pkgs, ... }:
      {
        home.packages = [
          # Avoid Zed remote falling back to its upstream glibc binary.
          pkgs.nodejs
        ]
        ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [ pkgs.brewCasks.zed ];
      };
  };
}
