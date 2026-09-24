{
  flake.modules.homeManager.development-rust =
    { pkgs, ... }:
    {
      key = "modules/features/development/rust.nix#homeManager.development-rust";

      home.packages = [ pkgs.rustup ];
    };
}
