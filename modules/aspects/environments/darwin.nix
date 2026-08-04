{ den, inputs, ... }:
let
  overlayPlan = import ../../../nix/lib/mk-overlays.nix { inherit inputs; } "aarch64-darwin";
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
  den.aspects.environments.darwin = {
    name = "dotfiles-darwin";
    includes = [
      den.aspects.environments.base
      den.aspects.environments.integrated-home-manager
    ];

    darwin = {
      imports = [ ../../../nix/modules/darwin/system.nix ];
      # The Den battery owns user creation and primary-user selection. Keep the
      # existing module argument only for services that need the account name.
      _module.args.username = "constantan";
      nixpkgs = {
        config.allowUnfree = true;
        overlays = overlayPlan.overlays;
      };
    };

    homeManager =
      { host, ... }:
      {
        imports = [
          ../../../nix/modules/options.nix
          homeModule
          ../../../nix/modules/darwin
        ];
        my = {
          hostKind = host.dotfiles.environment;
          dotfilesDir = host.dotfiles.source;
          standalone = false;
        };
      };
  };
}
