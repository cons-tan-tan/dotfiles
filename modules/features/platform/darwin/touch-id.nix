_: {
  flake.modules.darwin.platform-darwin = {
    key = "modules/features/platform/darwin/touch-id.nix#darwin.platform-darwin";
    security.pam.services.sudo_local.touchIdAuth = true;
  };
}
