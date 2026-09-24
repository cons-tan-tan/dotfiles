{
  flake.modules.homeManager.development-watchexec =
    { pkgs, ... }:
    {
      key = "modules/features/development/watchexec/default.nix#homeManager.development-watchexec";

      home.packages = [ pkgs.watchexec ];
    };
}
