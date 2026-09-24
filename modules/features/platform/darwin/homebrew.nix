_: {
  flake.modules.darwin.platform-homebrew = {
    key = "modules/features/platform/darwin/homebrew.nix#darwin.platform-homebrew";
    homebrew = {
      enable = true;
      onActivation = {
        # nix-darwin maps cleanup = "uninstall" to --force-cleanup, while
        # Homebrew Bundle accepts --cleanup for install-time cleanup.
        cleanup = "none";
        extraFlags = [ "--cleanup" ];
      };
      brews = [ ];
      casks = [ ];
      masApps = { };
    };
  };
}
