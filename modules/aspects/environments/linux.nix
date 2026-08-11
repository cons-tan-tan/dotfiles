{
  den,
  features,
  ...
}:
{
  den.aspects.environments.linux = {
    name = "dotfiles-linux";
    includes = [
      den.aspects.environments.base
      features.nixpkgs-home-overlays
      features.platform-context-linux-home
      features.nix-registry-home
      features.security-gpg-linux
      features.ghq-sync-systemd
      features.trash-systemd
      features.platform-linux
    ];
  };
}
