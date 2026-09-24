{
  flake.modules.darwin.network-tailscale = {
    key = "modules/features/network/tailscale.nix#darwin.network-tailscale";
    homebrew.casks = [ "tailscale-app" ];
  };
}
