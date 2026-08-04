_: {
  features.platform-wsl-memory = {
    name = "feature/platform/wsl/memory";
    nixos = {
      # Kill the pressured cgroup before the WSL VM exhausts its memory limit.
      systemd.oomd = {
        enable = true;
        enableUserSlices = true;
        settings.OOM.SwapUsedLimit = "80%";
      };
      systemd.slices."-".sliceConfig.ManagedOOMSwap = "kill";
      systemd.slices.user.sliceConfig = {
        MemoryAccounting = true;
        MemoryHigh = "24G";
        MemoryMax = "28G";
        MemorySwapMax = "4G";
      };

      # WSL API processes stay under init.scope rather than user.slice.
      systemd.units."init.scope" = {
        overrideStrategy = "asDropin";
        text = ''
          [Scope]
          OOMPolicy=continue
          ManagedOOMPreference=omit
          MemoryHigh=24G
          MemoryMax=28G
          MemorySwapMax=4G
        '';
      };

      # Builders run below nix-daemon and need a separate service boundary.
      systemd.services.nix-daemon.serviceConfig = {
        MemoryAccounting = true;
        MemoryHigh = "20G";
        MemoryMax = "24G";
        MemorySwapMax = "4G";
      };
    };
  };
}
