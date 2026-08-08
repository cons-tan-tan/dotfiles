{
  # MoZuKu builds its cabocha / crfpp C++ dependency chain from source and is
  # absent from the configured binary caches. Keep its upstream lock separate
  # from nixpkgs so routine nixpkgs updates do not rebuild that chain.
  flake-file.inputs.mozuku.url = "github:t3tra-dev/MoZuKu";

  features.development-mozuku = {
    name = "feature/development/mozuku";
    homeManager =
      { pkgs, ... }:
      {
        home.packages = [ pkgs.mozuku-lsp ];
      };
  };
}
