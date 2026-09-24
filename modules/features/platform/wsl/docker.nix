_: {
  flake.modules.nixos.platform-wsl-docker = {
    key = "modules/features/platform/wsl/docker.nix#nixos.platform-wsl-docker";
    virtualisation.docker = {
      enable = true;
      enableOnBoot = true;
    };
  };
}
