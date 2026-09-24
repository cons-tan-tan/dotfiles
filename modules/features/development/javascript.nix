{
  flake.modules.homeManager.development-javascript =
    { pkgs, ... }:
    {
      key = "modules/features/development/javascript.nix#homeManager.development-javascript";

      home.packages = [
        pkgs.ni
        pkgs.pnpm
      ];
    };
}
