_: {
  features.platform-wsl-docker = {
    name = "feature/platform/wsl/docker";
    nixos.virtualisation.docker = {
      enable = true;
      enableOnBoot = true;
    };
  };
}
