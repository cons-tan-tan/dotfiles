{
  features.registries-host = {
    name = "feature/registries/host";
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

  features.registries-home = {
    name = "feature/registries/home";
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
