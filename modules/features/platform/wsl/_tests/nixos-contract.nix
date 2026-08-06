{
  config,
  entityContext,
  lib,
  pkgs,
}:
let
  inherit (entityContext) username;
  linuxHomedir = entityContext.contexts.nixosWsl.homedir;
  windowsUsername = entityContext.windows.username;
  windowsHomedir = entityContext.windows.homedir;
  sourcePath = entityContext.contexts.nixosWsl.source;
  subjectUsername = username;
  home = config.home-manager.users.${subjectUsername};
  expectedInitScopeDropIn = ''
    [Scope]
    OOMPolicy=continue
    ManagedOOMPreference=omit
    MemoryHigh=24G
    MemoryMax=28G
    MemorySwapMax=4G
  '';

  contracts = {
    "wsl-base" = {
      actual = {
        enabled = config.wsl.enable;
        defaultUser = config.wsl.defaultUser;
        interopRegistered = config.wsl.interop.register;
        hasInteropRegistration = config.boot.binfmt.registrations ? WSLInterop;
        userLinger = config.users.users.${subjectUsername}.linger;
        gettyEnabled = config.services.getty.enable;
        gettyTargetWants = config.systemd.targets.getty.wants;
      };
      expected = {
        enabled = true;
        defaultUser = username;
        interopRegistered = true;
        hasInteropRegistration = true;
        userLinger = true;
        gettyEnabled = true;
        gettyTargetWants = [ ];
      };
    };

    "shell-integration" = {
      actual = {
        zshEnabled = config.programs.zsh.enable;
        userShell = lib.getExe config.users.users.${subjectUsername}.shell;
        homeZshEnabled = home.programs.zsh.enable;
        zoxideEnabled = home.programs.zoxide.enable;
        direnvIntegrated = home.programs.direnv.enableZshIntegration;
        starshipIntegrated = home.programs.starship.enableZshIntegration;
        zoxideIntegrated = home.programs.zoxide.enableZshIntegration;
        gpgAgentIntegrated = home.services.gpg-agent.enableZshIntegration;
        gpgSshSupport = home.services.gpg-agent.enableSshSupport;
        gitWtIntegrated = lib.hasInfix "git-wt --init zsh" home.programs.zsh.initContent;
      };
      expected = {
        zshEnabled = true;
        userShell = lib.getExe pkgs.zsh;
        homeZshEnabled = true;
        zoxideEnabled = true;
        direnvIntegrated = true;
        starshipIntegrated = true;
        zoxideIntegrated = true;
        gpgAgentIntegrated = true;
        gpgSshSupport = true;
        gitWtIntegrated = true;
      };
    };

    docker = {
      actual = {
        enabled = config.virtualisation.docker.enable;
        enableOnBoot = config.virtualisation.docker.enableOnBoot;
        userInDockerGroup = lib.elem "docker" config.users.users.${subjectUsername}.extraGroups;
        daemonHosts = config.virtualisation.docker.daemon.settings.hosts;
        listenOptions = config.virtualisation.docker.listenOptions;
        autoPruneEnabled = config.virtualisation.docker.autoPrune.enable;
      };
      expected = {
        enabled = true;
        enableOnBoot = true;
        userInDockerGroup = true;
        daemonHosts = [ "fd://" ];
        listenOptions = [ "/run/docker.sock" ];
        autoPruneEnabled = false;
      };
    };

    "memory-pressure-protection" = {
      actual = {
        oomd = {
          enabled = config.systemd.oomd.enable;
          rootMemoryPressureEnabled = config.systemd.oomd.enableRootSlice;
          rootSwapAction = config.systemd.slices."-".sliceConfig.ManagedOOMSwap;
          swapUsedLimit = config.systemd.oomd.settings.OOM.SwapUsedLimit;
          userSlicesEnabled = config.systemd.oomd.enableUserSlices;
        };
        userSlice = {
          inherit (config.systemd.slices.user.sliceConfig)
            MemoryAccounting
            MemoryHigh
            MemoryMax
            MemorySwapMax
            ;
        };
        initScope = {
          enabled = config.systemd.units."init.scope".enable;
          overrideStrategy = config.systemd.units."init.scope".overrideStrategy;
          dropIn = config.systemd.units."init.scope".text;
        };
        nixDaemon = {
          inherit (config.systemd.services.nix-daemon.serviceConfig)
            MemoryAccounting
            MemoryHigh
            MemoryMax
            MemorySwapMax
            ;
        };
      };
      expected = {
        oomd = {
          enabled = true;
          rootMemoryPressureEnabled = false;
          rootSwapAction = "kill";
          swapUsedLimit = "80%";
          userSlicesEnabled = true;
        };
        userSlice = {
          MemoryAccounting = true;
          MemoryHigh = "24G";
          MemoryMax = "28G";
          MemorySwapMax = "4G";
        };
        initScope = {
          enabled = true;
          overrideStrategy = "asDropin";
          dropIn = expectedInitScopeDropIn;
        };
        nixDaemon = {
          MemoryAccounting = true;
          MemoryHigh = "20G";
          MemoryMax = "24G";
          MemorySwapMax = "4G";
        };
      };
    };

    # modules/features/platform/wsl/base.nixの暫定対応と対になるcontract。
    # microsoft/WSL#40519を含むreleaseで再発しないことを確認後、
    # 対応する設定とこのcontractを同時に削除する。
    "temporary-wsl-workarounds" = {
      actual = {
        hostname = {
          configured = config.wsl.wslConf.network.hostname;
          directiveGenerated = lib.hasInfix "hostname=" config.environment.etc."wsl.conf".text;
        };
        userManagerRetry = {
          restart = config.systemd.services."user@".serviceConfig.Restart;
          restartSec = config.systemd.services."user@".serviceConfig.RestartSec;
          startLimitIntervalSec = config.systemd.services."user@".startLimitIntervalSec;
          startLimitBurst = config.systemd.services."user@".startLimitBurst;
          overrideStrategy = config.systemd.services."user@".overrideStrategy;
          restartIfChanged = config.systemd.services."user@".restartIfChanged;
        };
      };
      expected = {
        hostname = {
          configured = "";
          directiveGenerated = false;
        };
        userManagerRetry = {
          restart = "on-failure";
          restartSec = "250ms";
          startLimitIntervalSec = 5;
          startLimitBurst = 5;
          overrideStrategy = "asDropinIfExists";
          restartIfChanged = false;
        };
      };
    };

    "migration-pins" = {
      actual = {
        stateVersion = config.system.stateVersion;
        flakesEnabled = lib.elem "flakes" config.nix.settings.experimental-features;
        trustedUser = lib.elem username config.nix.settings."extra-trusted-users";
        minFree = config.nix.settings."min-free";
        maxFree = config.nix.settings."max-free";
        channelsEnabled = config.nix.channel.enable;
        tarballConfigPath = toString config.wsl.tarball.configPath;
      };
      expected = {
        stateVersion = "26.05";
        flakesEnabled = true;
        trustedUser = true;
        minFree = 34359738368;
        maxFree = 68719476736;
        channelsEnabled = false;
        tarballConfigPath = sourcePath;
      };
    };

    "home-manager-wiring" = {
      actual = {
        inherit (config.home-manager)
          useGlobalPkgs
          useUserPackages
          backupFileExtension
          ;
        username = home.home.username;
        homeDirectory = home.home.homeDirectory;
        hostKind = home.dotfiles.platform.environment;
        isWsl = home.dotfiles.platform.environment == "wsl";
        windowsUsername = home.dotfiles.platform.windows.username;
        windowsHomedir = home.dotfiles.platform.windows.homedir;
        dotfilesDir = home.dotfiles.platform.source;
      };
      expected = {
        useGlobalPkgs = true;
        useUserPackages = true;
        backupFileExtension = "hm-backup";
        username = username;
        homeDirectory = linuxHomedir;
        hostKind = "wsl";
        isWsl = true;
        inherit windowsUsername windowsHomedir;
        dotfilesDir = sourcePath;
      };
    };

    "codex-projection" = {
      actual = {
        activationAfter = home.home.activation.codexHooksConfig.after;
        rulesManaged = home.home.file ? ".codex/rules";
        rulesRecursive = home.home.file.".codex/rules".recursive;
      };
      expected = {
        activationAfter = [ "linkGeneration" ];
        rulesManaged = true;
        rulesRecursive = false;
      };
    };
  };

  failures = lib.filterAttrs (_: contract: contract.actual != contract.expected) contracts;
in
assert lib.assertMsg (failures == { }) ''
  NixOS-WSL configuration contract mismatches:
  ${builtins.toJSON failures}
'';
pkgs.runCommand "nixos-wsl-contract" { } ''touch "$out"''
