{ features, ... }:
{
  features.registries = {
    name = "feature/registries";
  };

  features.registries-host = {
    name = "feature/registries/host";
    includes = [ features.registries ];
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
    includes = [ features.registries ];
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
