_: {
  features.platform-homebrew = {
    name = "feature/platform/darwin/homebrew";
    darwin.homebrew = {
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
