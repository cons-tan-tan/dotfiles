{
  lib,
  pkgs,
  publicApps,
  subjects,
  username,
}:
let
  awsConfigHelper = subjects.awsConfigHelper;
  expectedArch = if pkgs.stdenv.hostPlatform.isx86_64 then "x86_64" else "aarch64";
  nhCleanupSystemd =
    if pkgs.stdenv.hostPlatform.isLinux then
      pkgs.callPackage ../../../packages/nh-cleanup-systemd {
        homedir = "/home/${username}";
        inherit username;
        nh = pkgs.nh;
        nix = pkgs.nix;
      }
    else
      null;
  nixStoreGrowthChecker = pkgs.callPackage ../../../packages/nix-store-growth-checker { };
  growthCheckerProbe = pkgs.writeShellApplication {
    name = "nix-store-growth-checker";
    text = ''
      printf '%s\n' "$@" >>"$GROWTH_CHECKER_ARGS"
      if [[ $1 == record ]]; then
        exit "''${GROWTH_RECORD_STATUS:-0}"
      fi
      exit "''${GROWTH_CHECKER_STATUS:-0}"
    '';
  };
  growthCleanupProbe = pkgs.writeShellApplication {
    name = "growth-cleanup-probe";
    text = ''
      printf '%s\n' "$@" >"$GROWTH_CLEANUP_ARGS"
      exit "''${GROWTH_CLEANUP_STATUS:-0}"
    '';
  };
  nhCleanGrowthRunnerContract = pkgs.callPackage ../../../packages/nh-clean-growth-runner {
    checker = growthCheckerProbe;
    cleanupCommand = lib.getExe growthCleanupProbe;
    cleanupArguments = [
      "--user"
      "start"
      "nh-clean.service"
    ];
    queryTimeout = "2s";
    maximumAgeSeconds = 789;
    retryIntervalSeconds = 456;
    storePath = "/test/store";
    thresholdBytes = 123;
  };
  nhCleanGrowthTimeoutRunnerContract = pkgs.callPackage ../../../packages/nh-clean-growth-runner {
    checker = nixStoreGrowthChecker;
    cleanupCommand = lib.getExe growthCleanupProbe;
    queryTimeout = "1s";
    maximumAgeSeconds = 789;
    retryIntervalSeconds = 456;
    storePath = "/tmp/nh-clean-growth-runner-timeout-store";
    thresholdBytes = 123;
  };
  claudeFixture = pkgs.writeShellApplication {
    name = "claude";
    text = ''
      : "''${TEST_TMPDIR:?}"
      printf 'path:%s\n' "$PATH" >"$TEST_TMPDIR/result"
      printf 'arg:%s\n' "$@" >>"$TEST_TMPDIR/result"
    '';
  };
  herdrPluginFixture = pkgs.runCommand "herdr-plugin-fixture" { } ''
    mkdir -p "$out"
    touch "$out/plugin.json"
  '';
  claudeWrapperTestPackage = pkgs.callPackage ../../../packages/claude-code/wrapped-package.nix {
    claudeCode = claudeFixture;
    herdrPlugin = herdrPluginFixture;
  };

  codexFixture = pkgs.writeShellApplication {
    name = "codex";
    text = ''
      : "''${TEST_TMPDIR:?}"
      printf 'arg:%s\n' "$@" >"$TEST_TMPDIR/result"
    '';
  };
  herdrSkillFixture = pkgs.runCommand "herdr-skill-fixture" { } ''
    mkdir -p "$out"
    touch "$out/SKILL.md"
  '';
  codexWrapperTestPackage = pkgs.callPackage ../../../packages/codex/wrapped-package.nix {
    codex = codexFixture;
    herdrSkillPath = "${herdrSkillFixture}/SKILL.md";
  };

  awsLoginFixture = pkgs.writeShellApplication {
    name = "aws";
    text = ''
      : "''${TEST_TMPDIR:?}"
      printf '%s\n' "$@" >"$TEST_TMPDIR/aws-args"
      if [[ "''${AWS_LOGIN_TEST_MODE:-success}" == fail ]]; then
        exit 7
      fi
      : "''${AWS_CONFIG_FILE:?}"
      printf '%s\n' 'login_session = fixture-session' >>"$AWS_CONFIG_FILE"
    '';
  };
  awsLoginTestBaseline = pkgs.writeText "aws-login-test-baseline" ''
    [profile test]
    output = json
  '';
  awsLoginTestPackage = pkgs.callPackage ../../../packages/aws/login-package.nix {
    awscli2 = awsLoginFixture;
    configHelper = awsConfigHelper;
    loginConfigFile = awsLoginTestBaseline;
  };
  awsConfigReconcileTestBaseline = pkgs.writeText "aws-config-reconcile-test-baseline" ''
    [profile test]
    region = baseline
    credential_process = command
  '';
  awsConfigReconcileTestPackage = pkgs.callPackage ../../../packages/aws/reconcile-package.nix {
    baselineFile = awsConfigReconcileTestBaseline;
    configHelper = awsConfigHelper;
    managedSections = [ "profile test" ];
  };

  piFixture = pkgs.writeShellApplication {
    name = "pi";
    text = ''
      : "''${TEST_TMPDIR:?}"
      printf 'package:%s\nskip:%s\ntelemetry:%s\n' \
        "$PI_PACKAGE_DIR" "$PI_SKIP_VERSION_CHECK" "$PI_TELEMETRY" >"$TEST_TMPDIR/result"
      printf 'arg:%s\n' "$@" >>"$TEST_TMPDIR/result"
    '';
  };
  piManagedPackageFixture = pkgs.runCommand "pi-managed-package-fixture" { } ''
    mkdir -p "$out"
  '';
  piWrapperTestPackage = pkgs.callPackage ../../../packages/pi/wrapped-package.nix {
    packageDir = piManagedPackageFixture;
    pi = piFixture;
  };

  herdrFixture = pkgs.writeShellApplication {
    name = "herdr";
    text = ''
      : "''${TEST_TMPDIR:?}"
      printf '%s\n' "$@" >"$TEST_TMPDIR/package-args"
    '';
  };
  herdrSleepFixture = pkgs.writeShellApplication {
    name = "herdr-sleep-fixture";
    text = "exit 0";
  };
  herdrWrapperTestPackage = pkgs.callPackage ../../../packages/herdr/wrapped-package.nix {
    herdr = herdrFixture;
    sleepBin = lib.getExe herdrSleepFixture;
  };

  drawioFixture = pkgs.writeShellApplication {
    name = "drawio";
    text = "exit 99";
  };
  drawioWrapperTestPackage = pkgs.callPackage ../../../packages/drawio-headless {
    drawio = drawioFixture;
  };

  wslRealpathFixture = pkgs.writeShellApplication {
    name = "realpath";
    text = ''
      : "''${TEST_TMPDIR:?}"
      printf '%s\n' "$#" "$@" >"$TEST_TMPDIR/package-realpath.args"
      printf '%s\n' "/package/resolved path"
    '';
  };
  wslpathFixture = pkgs.writeShellApplication {
    name = "wslpath";
    text = ''
      : "''${TEST_TMPDIR:?}"
      printf '%s\n' "$#" "$@" >"$TEST_TMPDIR/package-wslpath.args"
      printf '%s\n' 'Z:\package\resolved path'
    '';
  };
  wslHandlerFixture = pkgs.writeShellApplication {
    name = "rundll32.exe";
    text = ''
      : "''${TEST_TMPDIR:?}"
      printf '%s\n' "$#" "$@" >"$TEST_TMPDIR/package-handler.args"
    '';
  };
  wslOpenTestPackage = pkgs.callPackage ../../../packages/wsl-open {
    realpathBin = lib.getExe wslRealpathFixture;
    rundll32Bin = lib.getExe wslHandlerFixture;
    wslpathBin = lib.getExe wslpathFixture;
  };

  windowsCompanionDeployTestRoot = "/build/windows-companion-test/Users";
  windowsCompanionDeployMvFixture = pkgs.writeShellApplication {
    name = "windows-companion-deploy-mv-fixture";
    text = ''
      : "''${WINDOWS_COMPANION_DEPLOY_MV_STATE:?}"
      count=0
      if [[ -e $WINDOWS_COMPANION_DEPLOY_MV_STATE ]]; then
        read -r count <"$WINDOWS_COMPANION_DEPLOY_MV_STATE"
      fi
      count=$((count + 1))
      printf '%s\n' "$count" >"$WINDOWS_COMPANION_DEPLOY_MV_STATE"

      if [[ ''${WINDOWS_COMPANION_DEPLOY_MV_FAIL_AT:-} == "$count" ]]; then
        exit 71
      fi
      if [[ ''${WINDOWS_COMPANION_DEPLOY_MV_SIGNAL_BEFORE_AT:-} == "$count" ]]; then
        kill -TERM "$PPID"
        exit 143
      fi

      ${pkgs.coreutils}/bin/mv "$@"

      if [[ ''${WINDOWS_COMPANION_DEPLOY_MV_SIGNAL_AFTER_AT:-} == "$count" ]]; then
        kill -TERM "$PPID"
        exit 143
      fi
    '';
  };
  windowsCompanionDeployRsyncFixture = pkgs.writeShellApplication {
    name = "windows-companion-deploy-rsync-fixture";
    text = ''
      : "''${WINDOWS_COMPANION_DEPLOY_RSYNC_STATE:?}"
      count=0
      if [[ -e $WINDOWS_COMPANION_DEPLOY_RSYNC_STATE ]]; then
        read -r count <"$WINDOWS_COMPANION_DEPLOY_RSYNC_STATE"
      fi
      count=$((count + 1))
      printf '%s\n' "$count" >"$WINDOWS_COMPANION_DEPLOY_RSYNC_STATE"

      if [[ ''${WINDOWS_COMPANION_DEPLOY_RSYNC_FAIL_AT:-} == "$count" ]]; then
        exit 72
      fi

      ${pkgs.rsync}/bin/rsync "$@"

      if [[ ''${WINDOWS_COMPANION_DEPLOY_RSYNC_SIGNAL_AFTER_AT:-} == "$count" ]]; then
        kill -TERM "$PPID"
        exit 143
      fi
    '';
  };
  windowsCompanionDeployTestPackage = pkgs.callPackage ../../../packages/windows-companion-deploy {
    mvBin = lib.getExe windowsCompanionDeployMvFixture;
    rootPrefix = windowsCompanionDeployTestRoot;
    rsyncBin = lib.getExe windowsCompanionDeployRsyncFixture;
  };

in
{
  nativeBuildInputs = [
    pkgs.git
    pkgs.jq
    nhCleanGrowthRunnerContract
    nhCleanGrowthTimeoutRunnerContract
    nixStoreGrowthChecker
    awsConfigReconcileTestPackage
    awsLoginTestPackage
    claudeWrapperTestPackage
    codexWrapperTestPackage
    herdrWrapperTestPackage
    piWrapperTestPackage
    wslOpenTestPackage
  ]
  ++ lib.optional pkgs.stdenv.hostPlatform.isLinux drawioWrapperTestPackage;
  environment = {
    AWS_CONFIG_RECONCILE_TEST_PACKAGE = awsConfigReconcileTestPackage;
    AWS_LOGIN_TEST_PACKAGE = awsLoginTestPackage;
    CLAUDE_WRAPPER_TEST_PACKAGE = claudeWrapperTestPackage;
    CODEX_WRAPPER_TEST_PACKAGE = codexWrapperTestPackage;
    DRAWIO_WRAPPER_TEST_PACKAGE =
      if pkgs.stdenv.hostPlatform.isLinux then drawioWrapperTestPackage else "";
    HERDR_WRAPPER_TEST_PACKAGE = herdrWrapperTestPackage;
    HOST_APP_KIND = if pkgs.stdenv.hostPlatform.isDarwin then "darwin" else "linux-host";
    HOST_BUILD_PUBLIC_BIN = publicApps.build.program;
    HOST_EXPECTED_HM_LINUX = "constantan@linux-${expectedArch}";
    HOST_EXPECTED_HM_WSL = "constantan@wsl-${expectedArch}";
    HOST_EXPECTED_NIXOS_WSL = if pkgs.stdenv.hostPlatform.isx86_64 then "wsl" else "wsl-aarch64";
    HOST_SWITCH_PUBLIC_BIN = publicApps.switch.program;
    NH_CLEAN_GROWTH_RUNNER_BIN = lib.getExe nhCleanGrowthRunnerContract;
    NH_CLEAN_GROWTH_TIMEOUT_RUNNER_BIN = lib.getExe nhCleanGrowthTimeoutRunnerContract;
    NH_CLEANUP_SYSTEMD_PACKAGE = lib.optionalString pkgs.stdenv.hostPlatform.isLinux nhCleanupSystemd;
    NIX_STORE_GROWTH_CHECKER_BIN = lib.getExe nixStoreGrowthChecker;
    PI_WRAPPER_TEST_PACKAGE = piWrapperTestPackage;
    WSL_OPEN_TEST_PACKAGE = wslOpenTestPackage;
    WINDOWS_COMPANION_DEPLOY_TEST_BIN = lib.getExe windowsCompanionDeployTestPackage;
    WINDOWS_COMPANION_DEPLOY_TEST_ROOT = windowsCompanionDeployTestRoot;
  };
  requiredEnvironment = [
    "AWS_CONFIG_RECONCILE_TEST_PACKAGE"
    "AWS_LOGIN_TEST_PACKAGE"
    "CLAUDE_WRAPPER_TEST_PACKAGE"
    "CODEX_WRAPPER_TEST_PACKAGE"
    "HERDR_WRAPPER_TEST_PACKAGE"
    "HOST_APP_KIND"
    "HOST_BUILD_PUBLIC_BIN"
    "HOST_EXPECTED_HM_LINUX"
    "HOST_EXPECTED_HM_WSL"
    "HOST_EXPECTED_NIXOS_WSL"
    "HOST_SWITCH_PUBLIC_BIN"
    "NH_CLEAN_GROWTH_RUNNER_BIN"
    "NH_CLEAN_GROWTH_TIMEOUT_RUNNER_BIN"
    "NIX_STORE_GROWTH_CHECKER_BIN"
    "PI_WRAPPER_TEST_PACKAGE"
    "WSL_OPEN_TEST_PACKAGE"
    "WINDOWS_COMPANION_DEPLOY_TEST_BIN"
    "WINDOWS_COMPANION_DEPLOY_TEST_ROOT"
  ]
  ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
    "DRAWIO_WRAPPER_TEST_PACKAGE"
    "NH_CLEANUP_SYSTEMD_PACKAGE"
  ];
}
