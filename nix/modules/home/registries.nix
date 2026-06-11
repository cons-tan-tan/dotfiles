{ config, ... }:
{
  nix.registry.dotfiles = {
    from = {
      type = "indirect";
      id = "dotfiles";
    };

    to = {
      type = "path";
      path = config.my.dotfilesDir;
    };
  };
}
