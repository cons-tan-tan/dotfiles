{
  callPackage,
  coreutils,
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
  cleanupPolicy = import ../../lib/nh-clean-policy.nix;
  growth = cleanupPolicy.growth;
  checker = callPackage ../nix-store-growth-checker { inherit nix; };
  cleanupRunner = callPackage ../nh-clean-user { inherit nh nix; };
  resultRootPruner = callPackage ../nh-result-root-pruner { };
  policyRunner = callPackage ../nh-clean-growth-runner {
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
    ExecStart=${lib.getExe policyRunner} check ${statePath}
    TimeoutStartSec=infinity
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
    ExecStart=${lib.getExe resultRootPruner} --keep-minutes ${toString cleanupPolicy.resultRoots.keepMinutes}
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
      if (( EUID != 0 )); then
        echo "install-nh-cleanup-systemd must run as root" >&2
        exit 1
      fi

      readonly source_directory=${lib.escapeShellArg "${unitTree}/lib/systemd/system"}
      readonly target_directory=/etc/systemd/system
      readonly gcroot=/nix/var/nix/gcroots/nh-cleanup-systemd
      readonly next_gcroot="$gcroot.next"
      readonly lock_file=/run/lock/nh-cleanup-systemd.lock

      umask 0077
      exec 9>"$lock_file"
      flock --exclusive 9

      install -d -m 0755 "$(dirname "$gcroot")"
      # Keep the old closure rooted until every unit has been installed and
      # successfully reloaded. A failed update leaves both generations safe.
      ln -sfnT ${lib.escapeShellArg unitTree} "$next_gcroot"
      install -D -m 0644 "$source_directory/nh-clean.service" \
        "$target_directory/nh-clean.service"
      install -D -m 0644 "$source_directory/nh-clean.timer" \
        "$target_directory/nh-clean.timer"
      install -D -m 0644 "$source_directory/nh-clean-result-roots.service" \
        "$target_directory/nh-clean-result-roots.service"
      install -D -m 0644 "$source_directory/nh-clean-result-roots.timer" \
        "$target_directory/nh-clean-result-roots.timer"
      systemctl daemon-reload
      systemctl enable nh-clean.timer nh-clean-result-roots.timer
      systemctl restart nh-clean.timer nh-clean-result-roots.timer
      mv -Tf "$next_gcroot" "$gcroot"
    '';
  };
in
symlinkJoin {
  name = "nh-cleanup-systemd";
  paths = [
    installer
    unitTree
  ];
}
