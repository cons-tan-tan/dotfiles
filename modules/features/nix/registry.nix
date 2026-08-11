{
  features.nix-registry-host = {
    name = "feature/nix/registry/host";
    homeManager =
      { host, ... }:
      {
        nix.registry.dotfiles = {
          from = {
            type = "indirect";
            id = "dotfiles";
          };
          to = {
            type = "path";
            path = host.dotfiles.source;
          };
        };
      };
  };

  features.nix-registry-home = {
    name = "feature/nix/registry/home";
    homeManager =
      { home, ... }:
      {
        nix.registry.dotfiles = {
          from = {
            type = "indirect";
            id = "dotfiles";
          };
          to = {
            type = "path";
            path = home.dotfiles.source;
          };
        };
      };
  };
}
