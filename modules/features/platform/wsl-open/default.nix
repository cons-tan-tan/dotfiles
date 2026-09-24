{
  flake.modules.homeManager.platform-wsl-open =
    { pkgs, ... }:
    {
      key = "modules/features/platform/wsl-open/default.nix#homeManager.platform-wsl-open";

      home.packages = [ pkgs.dotfilesPackages.wsl-open ];
      home.sessionVariables.BROWSER = "wsl-open";
    };
}
