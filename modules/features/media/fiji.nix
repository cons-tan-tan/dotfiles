{
  flake.modules.darwin.media-fiji = {
    key = "modules/features/media/fiji.nix#darwin.media-fiji";
    homebrew.casks = [ "fiji" ];
  };
}
