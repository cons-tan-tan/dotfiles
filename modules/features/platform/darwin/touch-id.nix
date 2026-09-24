_: {
  flake.modules.darwin.platform-darwin-touch-id = {
    key = "modules/features/platform/darwin/touch-id.nix#darwin.platform-darwin-touch-id";
    security.pam.services.sudo_local.touchIdAuth = true;
  };
}
