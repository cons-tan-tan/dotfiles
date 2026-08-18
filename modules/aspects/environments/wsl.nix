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
      features.nix-registry-host
      features.security-oo7-dpapi
      features.security-ssh-signing
      features.agent-hunk-wsl
      features.platform-wsl-nixbuild
      features.ghq-sync-systemd
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
      features.nix-registry-home
      features.git-signing-openpgp
      features.agent-hunk-wsl
      features.security-gpg-wsl
      features.ghq-sync-systemd
      features.trash-systemd
      features.platform-wsl
    ];
  };
}
