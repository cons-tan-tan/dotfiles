{
  den,
  features,
  inputs,
  ...
}:
let
  overlayPlan = import ../../../nix/lib/mk-overlays.nix { inherit inputs; } "x86_64-linux";
  commonHomeModule =
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

  baseHomeModule = owner: {
    imports = [
      ../../../nix/modules/options.nix
      commonHomeModule
      ../../../nix/modules/linux
      ../../../nix/modules/wsl
    ];
    my = {
      hostKind = owner.dotfiles.environment;
      dotfilesDir = owner.dotfiles.source;
      standalone = false;
      windows = {
        inherit (owner.dotfiles.windows) username homedir;
      };
    };
  };

  standaloneHomeModule =
    owner:
    let
      base = baseHomeModule owner;
    in
    base
    // {
      my = base.my // {
        standalone = owner.dotfiles.standalone;
      };
      nixpkgs = {
        config.allowUnfree = true;
        overlays = overlayPlan.overlays;
      };
    };
in
{
  den.aspects.environments.wsl = {
    name = "dotfiles-wsl";
    includes = [
      den.aspects.environments.base
      den.aspects.environments.integrated-home-manager
      features.registries-host
      features.security-gpg-wsl
      features.source-control-ghq-sync-systemd
      features.trash-systemd
    ];

    nixos = {
      imports = [ ../../../nix/modules/nixos-wsl ];
      _module.args.username = "constantan";
      nixpkgs = {
        config.allowUnfree = true;
        overlays = overlayPlan.overlays;
      };

      # Keep the flake snapshot in the generated WSL tarball so recovery is
      # possible before the canonical clone exists.
      wsl.tarball.configPath = inputs.self.outPath;
      nix.channel.enable = false;
    };

    homeManager =
      { host, ... }:
      baseHomeModule host;
  };

  den.aspects.environments.standalone-wsl = {
    name = "dotfiles-standalone-wsl";
    includes = [
      den.aspects.environments.base
      features.registries-home
      features.security-gpg-wsl
      features.source-control-ghq-sync-systemd
      features.trash-systemd
    ];
    homeManager =
      { home, ... }:
      standaloneHomeModule home;
  };
}
