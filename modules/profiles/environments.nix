{ config, ... }:
let
  hm = config.flake.modules.homeManager;
  nixos = config.flake.modules.nixos;
  darwin = config.flake.modules.darwin;
in
{
  flake.modules.homeManager = {
    darwin.dotfiles.platform.environment = "darwin";
    linux.dotfiles.platform.environment = "linux";
    wsl.dotfiles.platform.environment = "wsl";
    standalone-wsl.dotfiles.platform.environment = "wsl";
    common.imports = [
      hm.common-home
      hm.agents-default
    ];
    darwin.imports = [
      hm.common
      hm.platform-darwin
      hm.nix-registry
      hm.git-signing-openpgp
      hm.security-gpg-darwin
      hm.ghq-sync-launchd
      hm.trash-darwin
    ];
    linux.imports = [
      hm.common
      hm.platform-linux
      hm.nix-registry
      hm.git-signing-openpgp
      hm.security-gpg-linux
      hm.ghq-sync-systemd
      hm.trash-systemd
    ];
    wsl.imports = [
      hm.common
      hm.platform-wsl
      hm.nix-registry
      hm.security-ssh-signing
      hm.agent-hunk-wsl
      hm.platform-wsl-nixbuild
      hm.ghq-sync-systemd
      hm.trash-systemd
    ];
    standalone-wsl.imports = [
      hm.common
      hm.platform-wsl
      hm.nix-registry
      hm.git-signing-openpgp
      hm.agent-hunk-wsl
      hm.security-gpg-wsl
      hm.ghq-sync-systemd
      hm.trash-systemd
    ];
  };
  flake.modules.nixos.wsl.imports = [
    nixos.platform-integrated-home-manager
    nixos.platform-wsl
    nixos.security-oo7-dpapi
    nixos.platform-wsl-nixbuild
  ];
  flake.modules.darwin.workstation.imports = [
    darwin.platform-integrated-home-manager
    darwin.platform-darwin
  ];
}
