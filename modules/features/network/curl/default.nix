{
  flake.modules.homeManager.network-curl = { pkgs, ... }: {
    key = "modules/features/network/curl/default.nix#homeManager.network-curl";

    home.packages = [ pkgs.curl ];
  };
}
