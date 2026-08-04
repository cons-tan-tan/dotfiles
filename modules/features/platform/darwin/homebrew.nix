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
      # Simple .app bundles stay in the packages feature's brew-nix overlay.
      # Installer packages, privileged helpers, and input methods remain real
      # Homebrew casks.
      casks = [
        "azookey"
        "fiji"
        "scroll-reverser"
        "tailscale-app"
      ];
      masApps = { };
    };
  };
}
