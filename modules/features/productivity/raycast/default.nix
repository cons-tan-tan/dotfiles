{ ... }:
{
  flake.modules.homeManager.productivity-raycast = {
    key = "modules/features/productivity/raycast/default.nix#homeManager.productivity-raycast";
    imports = [
      ({ pkgs, ... }: {
        home.packages = [ pkgs.raycast ];
      })
    ];
    dotfiles.unfreePackages = [ "raycast" ];
  };
}
