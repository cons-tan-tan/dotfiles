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
  expectedSystemCleanupCommand = lib.escapeShellArgs (
    [
      "clean"
      "all"
    ]
    ++ cleanupPolicy.arguments
  );
  expectedSystemCleanupExecutable = builtins.unsafeDiscardStringContext (
    lib.getExe config.programs.nh.package
  );
  systemCleanupScript = config.systemd.services.nh-clean.script;
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
      };
      expected = {
        systemProgramEnabled = false;
        systemCleanupEnabled = true;
        systemUser = "root";
        nixGcAutomatic = false;
        homeProgramEnabled = true;
        homeCleanupEnabled = false;
        homeCleanupServiceDefined = false;
        homeCleanupTimerDefined = false;
      };
    };

    "nh-cleanup-policy" = {
      actual = {
        dates = config.programs.nh.clean.dates;
        arguments = config.programs.nh.clean.extraArgs;
        commandUsesExecutable = lib.hasInfix expectedSystemCleanupExecutable systemCleanupScript;
        commandUsesArguments = lib.hasInfix expectedSystemCleanupCommand systemCleanupScript;
        pathHasNix = lib.elem config.nix.package config.systemd.services.nh-clean.path;
        nice = config.systemd.services.nh-clean.serviceConfig.Nice;
        ioClass = config.systemd.services.nh-clean.serviceConfig.IOSchedulingClass;
        timerOnCalendar = config.systemd.timers.nh-clean.timerConfig.OnCalendar;
        timerPersistent = config.systemd.timers.nh-clean.timerConfig.Persistent;
        timerWantedBy = config.systemd.timers.nh-clean.wantedBy;
      };
      expected = {
        dates = cleanupPolicy.dates;
        arguments = lib.escapeShellArgs cleanupPolicy.arguments;
        commandUsesExecutable = true;
        commandUsesArguments = true;
        pathHasNix = true;
        nice = 10;
        ioClass = "idle";
        timerOnCalendar = [ cleanupPolicy.dates ];
        timerPersistent = true;
        timerWantedBy = [ "timers.target" ];
      };
    };

    "nh-result-roots" = {
      actual = {
        serviceDefined = home.systemd.user.services ? nh-clean-result-roots;
        timerDefined = home.systemd.user.timers ? nh-clean-result-roots;
      };
      expected = {
        serviceDefined = true;
        timerDefined = true;
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
