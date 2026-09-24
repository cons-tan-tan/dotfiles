{
  flake.modules.homeManager.media-ffmpeg =
    { pkgs, ... }:
    {
      key = "modules/features/media/ffmpeg/default.nix#homeManager.media-ffmpeg";

      home.packages = [ pkgs.ffmpeg ];
    };
}
