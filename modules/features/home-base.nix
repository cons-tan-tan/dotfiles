{ features, inputs, ... }:
{
  flake-file.inputs.nix-index-database = {
    url = "github:nix-community/nix-index-database";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  features.home-base = {
    name = "feature/home-base";
    homeManager = {
      imports = [ inputs.nix-index-database.homeModules.default ];

      home = {
        stateVersion = "24.11";

        # home-manager and nixpkgs both follow the same unstable input, so the
        # release mismatch check remains useful.
        enableNixpkgsReleaseCheck = true;
      };

      programs.home-manager.enable = true;
      programs.nix-index-database.comma.enable = true;
    };
  };

  features.common-home = {
    name = "feature/common-home";
    includes = [
      features.home-base
      features.packages
      features.shell-zsh
      features.source-control-git
      features.source-control-git-wt
      features.source-control-gh
      features.source-control-ghq-sync
      features.cloud-aws
      features.cloud-gcloud
      features.network-curl
      features.security-gpg
      features.security-ssh
      features.registries
      features.trash
    ];
  };
}
