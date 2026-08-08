{
  features.media-ffmpeg = {
    name = "feature/media/ffmpeg";
    homeManager =
      { pkgs, ... }:
      {
        home.packages = [ pkgs.ffmpeg ];
      };
  };
}
