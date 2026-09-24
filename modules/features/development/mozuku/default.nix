{
  # MoZuKu builds its cabocha / crfpp C++ dependency chain from source and is
  # absent from the configured binary caches. Keep its upstream lock separate
  # from nixpkgs so routine nixpkgs updates do not rebuild that chain.
  flake-file.inputs.mozuku.url = "github:t3tra-dev/MoZuKu";

  flake.modules.homeManager.development-mozuku =
    { pkgs, ... }:
    {
      key = "modules/features/development/mozuku/default.nix#homeManager.development-mozuku";

      home.packages = [ pkgs.mozuku-lsp ];
    };
}
