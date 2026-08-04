_: {
  features.platform-darwin-system = {
    name = "feature/platform/darwin/system";
    darwin = {
      # Determinate Nix owns the daemon and /etc/nix configuration.
      nix.enable = false;
      system.stateVersion = 5;
    };
  };
}
