{
  features.media-aqua-voice = {
    name = "feature/media/aqua-voice";
    homeManager = { pkgs, ... }: {
      home.packages = [ pkgs.brewCasks.aqua-voice ];
    };
  };
}
