{
  den,
  features,
  ...
}:
{
  den.aspects.environments.darwin = {
    name = "dotfiles-darwin";
    includes = [
      den.aspects.environments.base
      features.nixpkgs-host-overlays
      features.platform-context-darwin-host
      features.platform-integrated-home-manager
      features.nix-registry-host
      features.security-gpg-darwin
      features.source-control-ghq-sync-launchd
      features.trash-darwin
      features.platform-darwin
    ];
  };
}
