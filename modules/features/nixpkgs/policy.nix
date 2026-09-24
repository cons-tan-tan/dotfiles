{ lib, ... }:
{
  flake.modules.homeManager.home-base = {
    key = "modules/features/nixpkgs/policy.nix#homeManager.home-base";
    options.dotfiles.unfreePackages = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Unfree package names required by the selected home features.";
    };
  };
}
