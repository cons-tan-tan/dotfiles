{
  flake.modules.darwin.platform-darwin-scroll-reverser = {
    key = "modules/features/platform/darwin/scroll-reverser.nix#darwin.platform-darwin-scroll-reverser";
    homebrew.casks = [ "scroll-reverser" ];
  };
}
