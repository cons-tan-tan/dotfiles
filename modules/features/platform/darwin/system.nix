_: {
  flake.modules.darwin.platform-darwin = {
    key = "modules/features/platform/darwin/system.nix#darwin.platform-darwin";
    # Determinate Nix owns the daemon and /etc/nix configuration.
    nix.enable = false;
    system.stateVersion = 5;
  };
}
