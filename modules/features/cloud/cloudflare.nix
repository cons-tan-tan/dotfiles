{
  flake.modules.homeManager.cloud-cloudflare =
    { pkgs, ... }:
    {
      key = "modules/features/cloud/cloudflare.nix#homeManager.cloud-cloudflare";

      home.packages = [ pkgs.cf ];
    };
}
