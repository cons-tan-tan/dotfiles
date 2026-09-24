{
  flake.modules.homeManager.media-aqua-voice = { pkgs, ... }: {
    key = "modules/features/media/aqua-voice/default.nix#homeManager.media-aqua-voice";

    home.packages = [ pkgs.brewCasks.aqua-voice ];
  };
}
