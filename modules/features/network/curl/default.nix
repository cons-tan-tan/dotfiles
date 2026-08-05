{ ... }:
{
  features.network-curl = {
    name = "feature/network/curl";
    homeManager = { pkgs, ... }: {
      home.packages = [ pkgs.curl ];
    };
  };
}
