_: {
  flake.modules.darwin.platform-darwin-system = {
    key = "modules/features/platform/darwin/system.nix#darwin.platform-darwin-system";
    # Determinate Nix owns the daemon and /etc/nix configuration.
    nix.enable = false;
    system.stateVersion = 5;
  };
}
