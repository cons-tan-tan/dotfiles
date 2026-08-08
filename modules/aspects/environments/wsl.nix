{
  den,
  features,
  ...
}:
{
  den.aspects.environments.wsl = {
    name = "dotfiles-wsl";
    includes = [
      den.aspects.environments.base
      features.nixpkgs-host-overlays
      features.platform-context-wsl-host
      features.platform-integrated-home-manager
      features.registries-host
      features.agent-hunk-wsl
      features.shell-direnv-nixbuild-wsl
      features.source-control-ghq-sync-systemd
      features.trash-systemd
      features.platform-wsl
    ];
  };

  den.aspects.environments.standalone-wsl = {
    name = "dotfiles-standalone-wsl";
    includes = [
      den.aspects.environments.base
      features.nixpkgs-home-overlays
      features.platform-context-wsl-home
      features.registries-home
      features.agent-hunk-wsl
      features.security-gpg-wsl
      features.source-control-ghq-sync-systemd
      features.trash-systemd
      features.platform-wsl
    ];
  };
}
