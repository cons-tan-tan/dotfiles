{
  flake.modules.homeManager.development-go =
    { pkgs, ... }:
    {
      key = "modules/features/development/go.nix#homeManager.development-go";

      home.packages = [ (pkgs.callPackage ./_packages/go.nix { }) ];
    };
}
