{ config, ... }:
{
  flake.modules.homeManager.home-base = {
    key = "modules/features/home-base.nix#homeManager.home-base";
    home = {
      stateVersion = "24.11";

      # home-manager and nixpkgs both follow the same unstable input, so the
      # release mismatch check remains useful.
      enableNixpkgsReleaseCheck = true;
    };

    programs.home-manager.enable = true;
  };

  flake.modules.homeManager.common-home = {
    key = "modules/features/home-base.nix#homeManager.common-home";
    imports = [
      config.flake.modules.homeManager.home-base
      config.flake.modules.homeManager.nix-default
      config.flake.modules.homeManager.ci-tools
      config.flake.modules.homeManager.cli-tools
      config.flake.modules.homeManager.development-default
      config.flake.modules.homeManager.editors-default
      config.flake.modules.homeManager.media-ffmpeg
      config.flake.modules.homeManager.shell-zsh
      config.flake.modules.homeManager.git
      config.flake.modules.homeManager.git-wt
      config.flake.modules.homeManager.gh
      config.flake.modules.homeManager.ghq-sync
      config.flake.modules.homeManager.terminal-default
      config.flake.modules.homeManager.cloud-aws
      config.flake.modules.homeManager.cloud-gcloud
      config.flake.modules.homeManager.network-curl
      config.flake.modules.homeManager.security-gpg
      config.flake.modules.homeManager.security-secrets
      config.flake.modules.homeManager.security-ssh
      config.flake.modules.homeManager.safe-deletion
    ];
  };
}
