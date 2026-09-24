{
  flake.modules.homeManager.nix-registry = { config, ... }: {
    key = "modules/features/nix/registry.nix#homeManager.nix-registry";

    nix.registry.dotfiles = {
      from = {
        type = "indirect";
        id = "dotfiles";
      };
      to = {
        type = "path";
        path = config.dotfiles.platform.source;
      };
    };
  };
}
