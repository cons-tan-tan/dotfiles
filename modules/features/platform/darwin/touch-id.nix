_: {
  features.platform-darwin-touch-id = {
    name = "feature/platform/darwin/touch-id";
    darwin.security.pam.services.sudo_local.touchIdAuth = true;
  };
}
