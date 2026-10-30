_: {
  flake.modules.darwin.platform-darwin = {
    key = "modules/features/platform/darwin/touch-id.nix#darwin.platform-darwin";
    security.pam.services.sudo_local = {
      touchIdAuth = true;
      # Reattach sudo to the GUI session when launched from Herdr's background server.
      reattach = true;
    };
  };
}
