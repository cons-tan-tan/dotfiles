{
  den,
  features,
  inputs,
  ...
}:
let
  overlayPlan = import ../../../nix/lib/mk-overlays.nix { inherit inputs; } "x86_64-linux";
  homeModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    import ../../../nix/modules/home {
      inherit
        config
        inputs
        lib
        pkgs
        ;
    };
in
{
  den.aspects.environments.linux = {
    name = "dotfiles-linux";
    includes = [
      den.aspects.environments.base
      features.registries-home
      features.security-gpg-linux
      features.source-control-ghq-sync-systemd
      features.trash-systemd
    ];

    homeManager =
      { home, ... }:
      {
        imports = [
          ../../../nix/modules/options.nix
          homeModule
          ../../../nix/modules/linux
        ];
        my = {
          hostKind = home.dotfiles.environment;
          dotfilesDir = home.dotfiles.source;
          standalone = home.dotfiles.standalone;
        };
        nixpkgs = {
          config.allowUnfree = true;
          overlays = overlayPlan.overlays;
        };
      };
  };
}
