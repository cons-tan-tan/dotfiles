{
  callPackage,
  coreutils,
  enableTestOverrides ? false,
  homedir,
  lib,
  nh,
  nix,
  systemd,
  symlinkJoin,
  username,
  util-linux,
  writeShellApplication,
  writeTextDir,
}:
let
  cleanupPolicy = import ../../_data/cleanup-policy.nix;
  growth = cleanupPolicy.growth;
  checker = callPackage ../store-growth-checker { inherit nix; };
  cleanupRunner = callPackage ../clean-user { inherit nh nix; };
  resultRootPruner = callPackage ../result-root-pruner { };
  policyRunner = callPackage ../clean-growth-runner {
    inherit checker;
    cleanupCommand = lib.getExe cleanupRunner;
    inherit (growth)
      maximumAgeSeconds
      queryTimeout
      retryIntervalSeconds
      thresholdBytes
      ;
  };
  statePath = "/var/lib/${growth.stateDirectory}";
  lock = import ../../_interface/cleanup-lock.nix {
    inherit coreutils lib username;
  };
  lockPreparation = lib.concatMapStringsSep "\n" (
    command: "ExecStartPre=${command}"
  ) lock.preparationCommands;
  serviceUnit = writeTextDir "lib/systemd/system/nh-clean.service" ''
    [Unit]
    Description=Clean Nix store after growth or maximum age
    After=nix-daemon.socket
    Wants=nix-daemon.socket

    [Service]
    Type=oneshot
    User=${username}
    Environment=HOME=${homedir}
    WorkingDirectory=${homedir}
    Nice=10
    IOSchedulingClass=idle
    StateDirectory=${growth.stateDirectory}
    StateDirectoryMode=0750
    ${lockPreparation}
    ExecStart=${lib.getExe' util-linux "flock"} --exclusive ${lock.cleanupFile} ${lib.getExe policyRunner} check ${statePath}
    TimeoutStartSec=${growth.cleanupTimeout}
  '';
  timerUnit = writeTextDir "lib/systemd/system/nh-clean.timer" ''
    [Unit]
    Description=Check Nix store cleanup policy periodically

    [Timer]
    OnBootSec=${growth.checkInterval}
    OnUnitActiveSec=${growth.checkInterval}
    AccuracySec=30s
    Unit=nh-clean.service

    [Install]
    WantedBy=timers.target
  '';
  resultRootServiceUnit = writeTextDir "lib/systemd/system/nh-clean-result-roots.service" ''
    [Unit]
    Description=Prune stale Nix build result roots

    [Service]
    Type=oneshot
    User=${username}
    Environment=HOME=${homedir}
    WorkingDirectory=${homedir}
    Nice=10
    IOSchedulingClass=idle
    ${lockPreparation}
    ExecStart=${lib.getExe' util-linux "flock"} --exclusive ${lock.cleanupFile} ${lib.getExe resultRootPruner} --keep-minutes ${toString cleanupPolicy.resultRoots.keepMinutes}
  '';
  resultRootTimerUnit = writeTextDir "lib/systemd/system/nh-clean-result-roots.timer" ''
    [Unit]
    Description=Weekly cleanup of stale Nix build result roots

    [Timer]
    OnCalendar=${cleanupPolicy.resultRoots.dates}
    Persistent=true
    RandomizedDelaySec=30min
    Unit=nh-clean-result-roots.service

    [Install]
    WantedBy=timers.target
  '';
  unitTree = symlinkJoin {
    name = "nh-cleanup-systemd-units";
    paths = [
      serviceUnit
      timerUnit
      resultRootServiceUnit
      resultRootTimerUnit
    ];
  };
  installer = writeShellApplication {
    name = "install-nh-cleanup-systemd";
    runtimeInputs = [
      coreutils
      systemd
      util-linux
    ];
    text = ''
      readonly cleanup_user=${lib.escapeShellArg username}
      readonly source_directory=${lib.escapeShellArg "${unitTree}/lib/systemd/system"}
    ''
    + (
      if enableTestOverrides then
        ''
          readonly target_directory="''${NH_CLEANUP_TEST_TARGET_DIRECTORY:?}"
          readonly gcroot="''${NH_CLEANUP_TEST_GCROOT:?}"
          readonly lock_directory="''${NH_CLEANUP_TEST_LOCK_DIRECTORY:?}"
          readonly systemctl_command="''${NH_CLEANUP_TEST_SYSTEMCTL_BIN:?}"
          readonly allow_unprivileged=true
          readonly manage_ownership=false
        ''
      else
        ''
          readonly target_directory=/etc/systemd/system
          readonly gcroot=/nix/var/nix/gcroots/nh-cleanup-systemd
          readonly lock_directory=${lock.directory}
          readonly systemctl_command=${lib.escapeShellArg (lib.getExe' systemd "systemctl")}
          readonly allow_unprivileged=false
          readonly manage_ownership=true
        ''
    )
    + ''
      readonly next_gcroot="$gcroot.next"
      readonly unit_tree=${lib.escapeShellArg unitTree}
      readonly cleanup_lock_file="$lock_directory/cleanup.lock"
      readonly installer_lock_file="$lock_directory/installer.lock"
    ''
    + builtins.readFile ./install-nh-cleanup-systemd.sh;
  };
in
symlinkJoin {
  name = "nh-cleanup-systemd";
  paths = [
    installer
    unitTree
  ];
}
