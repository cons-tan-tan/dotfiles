{
  config,
  lib,
  linuxHomedir,
  pkgs,
  sourcePath,
  username,
  windowsHomedir,
  windowsUsername,
}:
let
  home = config.home-manager.users.${username};
  cleanupPolicy = import ../lib/nh-clean-policy.nix;
  growthChecker = pkgs.callPackage ../packages/nix-store-growth-checker {
    nix = config.nix.package;
  };
  cleanupRunner = pkgs.callPackage ../packages/nh-clean-user {
    nh = config.programs.nh.package;
    nix = config.nix.package;
    scope = "all";
  };
  resultRootPruner = pkgs.callPackage ../packages/nh-result-root-pruner { };
  growthStatePath = "/var/lib/${cleanupPolicy.growth.stateDirectory}";
  growthRunner = pkgs.callPackage ../packages/nh-clean-growth-runner {
    checker = growthChecker;
    cleanupCommand = lib.getExe cleanupRunner;
    inherit (cleanupPolicy.growth)
      maximumAgeSeconds
      queryTimeout
      retryIntervalSeconds
      thresholdBytes
      ;
  };
  growthRunnerBin = lib.getExe growthRunner;
  expectedGrowthCheckCommand = "${growthRunnerBin} check ${growthStatePath}";
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
        userLinger = config.users.users.${username}.linger;
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
        userShell = lib.getExe config.users.users.${username}.shell;
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
        userInDockerGroup = lib.elem "docker" config.users.users.${username}.extraGroups;
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

    "nh-cleanup-ownership" = {
      actual = {
        systemProgramEnabled = config.programs.nh.enable;
        systemCleanupEnabled = config.programs.nh.clean.enable;
        systemUser = config.systemd.services.nh-clean.serviceConfig.User;
        nixGcAutomatic = config.nix.gc.automatic;
        homeProgramEnabled = home.programs.nh.enable;
        homeCleanupEnabled = home.programs.nh.clean.enable;
        homeCleanupServiceDefined = home.systemd.user.services ? nh-clean;
        homeCleanupTimerDefined = home.systemd.user.timers ? nh-clean;
        homeGrowthServiceDefined = home.systemd.user.services ? nh-clean-growth-check;
        homeGrowthTimerDefined = home.systemd.user.timers ? nh-clean-growth-check;
      };
      expected = {
        systemProgramEnabled = false;
        systemCleanupEnabled = false;
        systemUser = "root";
        nixGcAutomatic = false;
        homeProgramEnabled = true;
        homeCleanupEnabled = false;
        homeCleanupServiceDefined = false;
        homeCleanupTimerDefined = false;
        homeGrowthServiceDefined = false;
        homeGrowthTimerDefined = false;
      };
    };

    "nh-cleanup-policy" = {
      actual = {
        description = config.systemd.services.nh-clean.description;
        type = config.systemd.services.nh-clean.serviceConfig.Type;
        after = config.systemd.services.nh-clean.after;
        wants = config.systemd.services.nh-clean.wants;
        nice = config.systemd.services.nh-clean.serviceConfig.Nice;
        ioClass = config.systemd.services.nh-clean.serviceConfig.IOSchedulingClass;
        stateDirectory = config.systemd.services.nh-clean.serviceConfig.StateDirectory;
        stateDirectoryMode = config.systemd.services.nh-clean.serviceConfig.StateDirectoryMode;
        command = config.systemd.services.nh-clean.serviceConfig.ExecStart;
        timeoutStart = config.systemd.services.nh-clean.serviceConfig.TimeoutStartSec;
        timerOnBoot = config.systemd.timers.nh-clean.timerConfig.OnBootSec;
        timerOnActive = config.systemd.timers.nh-clean.timerConfig.OnUnitActiveSec;
        timerAccuracy = config.systemd.timers.nh-clean.timerConfig.AccuracySec;
        timerWantedBy = config.systemd.timers.nh-clean.wantedBy;
      };
      expected = {
        description = "Clean Nix store after growth or maximum age";
        type = "oneshot";
        after = [ "nix-daemon.socket" ];
        wants = [ "nix-daemon.socket" ];
        nice = 10;
        ioClass = "idle";
        stateDirectory = cleanupPolicy.growth.stateDirectory;
        stateDirectoryMode = "0750";
        command = expectedGrowthCheckCommand;
        timeoutStart = "infinity";
        timerOnBoot = cleanupPolicy.growth.checkInterval;
        timerOnActive = cleanupPolicy.growth.checkInterval;
        timerAccuracy = "30s";
        timerWantedBy = [ "timers.target" ];
      };
    };

    "nh-growth-cleanup" = {
      actual = {
        serviceDefined = config.systemd.services ? nh-clean-growth-check;
        timerDefined = config.systemd.timers ? nh-clean-growth-check;
      };
      expected = {
        serviceDefined = false;
        timerDefined = false;
      };
    };

    "nh-result-roots" = {
      actual = {
        homeServiceDefined = home.systemd.user.services ? nh-clean-result-roots;
        homeTimerDefined = home.systemd.user.timers ? nh-clean-result-roots;
        systemServiceDefined = config.systemd.services ? nh-clean-result-roots;
        systemTimerDefined = config.systemd.timers ? nh-clean-result-roots;
        user = config.systemd.services.nh-clean-result-roots.serviceConfig.User;
        command = config.systemd.services.nh-clean-result-roots.serviceConfig.ExecStart;
        calendar = config.systemd.timers.nh-clean-result-roots.timerConfig.OnCalendar;
        persistent = config.systemd.timers.nh-clean-result-roots.timerConfig.Persistent;
      };
      expected = {
        homeServiceDefined = false;
        homeTimerDefined = false;
        systemServiceDefined = true;
        systemTimerDefined = true;
        user = username;
        command = "${lib.getExe resultRootPruner} --keep-minutes ${toString cleanupPolicy.resultRoots.keepMinutes}";
        calendar = cleanupPolicy.resultRoots.dates;
        persistent = true;
      };
    };

    # nix/modules/nixos-wsl/default.nixの暫定対応と対になるcontract。
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
        channelsEnabled = config.nix.channel.enable;
        tarballConfigPath = toString config.wsl.tarball.configPath;
      };
      expected = {
        stateVersion = "26.05";
        flakesEnabled = true;
        trustedUser = true;
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
        hostKind = home.my.hostKind;
        isWsl = home.my.isWsl;
        windowsUsername = home.my.windows.username;
        windowsHomedir = home.my.windows.homedir;
        dotfilesDir = home.my.dotfilesDir;
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
