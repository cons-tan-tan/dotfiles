{ features, ... }:
{
  features.home-base = {
    name = "feature/home-base";
    homeManager = {
      home = {
        stateVersion = "24.11";

        # home-manager and nixpkgs both follow the same unstable input, so the
        # release mismatch check remains useful.
        enableNixpkgsReleaseCheck = true;
      };

      programs.home-manager.enable = true;
    };
  };

  features.common-home = {
    name = "feature/common-home";
    includes = [
      features.home-base
      features.nix-default
      features.ci-tools
      features.cli-tools
      features.development-default
      features.editors-default
      features.media-ffmpeg
      features.shell-zsh
      features.git
      features.git-wt
      features.gh
      features.ghq-sync
      features.terminal-default
      features.cloud-aws
      features.cloud-gcloud
      features.network-curl
      features.security-gpg
      features.security-secrets
      features.security-ssh
      features.safe-deletion
    ];
  };
}
