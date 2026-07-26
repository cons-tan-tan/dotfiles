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
  actual = {
    wslEnabled = config.wsl.enable;
    defaultUser = config.wsl.defaultUser;
    interopRegistered = config.wsl.interop.register;
    hasWslInteropRegistration = config.boot.binfmt.registrations ? WSLInterop;
    userLinger = config.users.users.${username}.linger;
    shell = {
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
    docker = {
      enabled = config.virtualisation.docker.enable;
      enableOnBoot = config.virtualisation.docker.enableOnBoot;
      userInDockerGroup = lib.elem "docker" config.users.users.${username}.extraGroups;
      daemonHosts = config.virtualisation.docker.daemon.settings.hosts;
      listenOptions = config.virtualisation.docker.listenOptions;
      autoPruneEnabled = config.virtualisation.docker.autoPrune.enable;
    };
    nhCleanup = {
      systemProgramEnabled = config.programs.nh.enable;
      systemCleanupEnabled = config.programs.nh.clean.enable;
      systemCleanupDates = config.programs.nh.clean.dates;
      systemCleanupArgs = config.programs.nh.clean.extraArgs;
      systemCommand = config.systemd.services.nh-clean.script;
      systemPathHasNix = lib.elem config.nix.package config.systemd.services.nh-clean.path;
      systemUser = config.systemd.services.nh-clean.serviceConfig.User;
      systemNice = config.systemd.services.nh-clean.serviceConfig.Nice;
      systemIoClass = config.systemd.services.nh-clean.serviceConfig.IOSchedulingClass;
      timerOnCalendar = config.systemd.timers.nh-clean.timerConfig.OnCalendar;
      timerPersistent = config.systemd.timers.nh-clean.timerConfig.Persistent;
      timerWantedBy = config.systemd.timers.nh-clean.wantedBy;
      nixGcAutomatic = config.nix.gc.automatic;
      homeProgramEnabled = home.programs.nh.enable;
      homeCleanupEnabled = home.programs.nh.clean.enable;
      homeCleanupServiceDefined = home.systemd.user.services ? nh-clean;
      homeCleanupTimerDefined = home.systemd.user.timers ? nh-clean;
      resultRootServiceDefined = home.systemd.user.services ? nh-clean-result-roots;
      resultRootTimerDefined = home.systemd.user.timers ? nh-clean-result-roots;
    };
    wslConsole = {
      gettyEnabled = config.services.getty.enable;
      gettyTargetWants = config.systemd.targets.getty.wants;
    };
    # nix/modules/nixos-wsl/default.nixの暫定対応と対になるcontract。
    # microsoft/WSL#40519を含むreleaseで再発しないことを確認後、
    # 対応する設定とこのattrsetを同時に削除する。
    temporaryWslWorkarounds = {
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
    stateVersion = config.system.stateVersion;
    flakesEnabled = lib.elem "flakes" config.nix.settings.experimental-features;
    trustedUser = lib.elem username config.nix.settings."extra-trusted-users";
    channelsEnabled = config.nix.channel.enable;
    tarballConfigPath = toString config.wsl.tarball.configPath;
    inherit (config.home-manager)
      useGlobalPkgs
      useUserPackages
      backupFileExtension
      ;
    homeUsername = home.home.username;
    homeDirectory = home.home.homeDirectory;
    hostKind = home.my.hostKind;
    isWsl = home.my.isWsl;
    windowsUsername = home.my.windows.username;
    windowsHomedir = home.my.windows.homedir;
    dotfilesDir = home.my.dotfilesDir;
    codexActivationAfter = home.home.activation.codexHooksConfig.after;
  };
  expected = {
    wslEnabled = true;
    defaultUser = username;
    interopRegistered = true;
    hasWslInteropRegistration = true;
    userLinger = true;
    shell = {
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
    docker = {
      enabled = true;
      enableOnBoot = true;
      userInDockerGroup = true;
      daemonHosts = [ "fd://" ];
      listenOptions = [ "/run/docker.sock" ];
      autoPruneEnabled = false;
    };
    nhCleanup = {
      systemProgramEnabled = false;
      systemCleanupEnabled = true;
      systemCleanupDates = "*-*-* 00/6:00:00";
      systemCleanupArgs = "--keep 5 --keep-since 1d --no-gcroots --no-direnv";
      systemCommand = "exec ${lib.getExe config.programs.nh.package} clean all --keep 5 --keep-since 1d --no-gcroots --no-direnv";
      systemPathHasNix = true;
      systemUser = "root";
      systemNice = 10;
      systemIoClass = "idle";
      timerOnCalendar = [ "*-*-* 00/6:00:00" ];
      timerPersistent = true;
      timerWantedBy = [ "timers.target" ];
      nixGcAutomatic = false;
      homeProgramEnabled = true;
      homeCleanupEnabled = false;
      homeCleanupServiceDefined = false;
      homeCleanupTimerDefined = false;
      resultRootServiceDefined = true;
      resultRootTimerDefined = true;
    };
    wslConsole = {
      gettyEnabled = true;
      gettyTargetWants = [ ];
    };
    temporaryWslWorkarounds = {
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
    stateVersion = "26.05";
    flakesEnabled = true;
    trustedUser = true;
    channelsEnabled = false;
    tarballConfigPath = sourcePath;
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "hm-backup";
    homeUsername = username;
    homeDirectory = linuxHomedir;
    hostKind = "wsl";
    isWsl = true;
    inherit windowsUsername windowsHomedir;
    dotfilesDir = sourcePath;
    codexActivationAfter = [ "linkGeneration" ];
  };
in
assert lib.assertMsg (actual == expected) ''
  NixOS-WSL configuration contract mismatch:
  expected ${builtins.toJSON expected}
  actual ${builtins.toJSON actual}
'';
pkgs.runCommand "nixos-wsl-contract" { } ''touch "$out"''
