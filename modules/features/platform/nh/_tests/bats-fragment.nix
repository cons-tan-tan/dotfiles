{
  lib,
  pkgs,
  username,
}:
let
  cleanupSystemd =
    if pkgs.stdenv.hostPlatform.isLinux then
      pkgs.callPackage ../_packages/cleanup-systemd {
        homedir = "/home/${username}";
        inherit username;
        nh = pkgs.nh;
        nix = pkgs.nix;
      }
    else
      null;
  storeGrowthChecker = pkgs.callPackage ../_packages/store-growth-checker { };
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
  cleanGrowthRunnerContract = pkgs.callPackage ../_packages/clean-growth-runner {
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
  cleanGrowthTimeoutRunnerContract = pkgs.callPackage ../_packages/clean-growth-runner {
    checker = storeGrowthChecker;
    cleanupCommand = lib.getExe growthCleanupProbe;
    queryTimeout = "1s";
    maximumAgeSeconds = 789;
    retryIntervalSeconds = 456;
    storePath = "/tmp/nh-clean-growth-runner-timeout-store";
    thresholdBytes = 123;
  };
in
{
  group = "shellWrappers";
  fixture = {
    nativeBuildInputs = [
      cleanGrowthRunnerContract
      cleanGrowthTimeoutRunnerContract
      storeGrowthChecker
    ];
    environment = {
      NH_CLEAN_GROWTH_RUNNER_BIN = lib.getExe cleanGrowthRunnerContract;
      NH_CLEAN_GROWTH_TIMEOUT_RUNNER_BIN = lib.getExe cleanGrowthTimeoutRunnerContract;
      NH_CLEANUP_SYSTEMD_PACKAGE = lib.optionalString pkgs.stdenv.hostPlatform.isLinux cleanupSystemd;
      NIX_STORE_GROWTH_CHECKER_BIN = lib.getExe storeGrowthChecker;
    };
    requiredEnvironment = [
      "NH_CLEAN_GROWTH_RUNNER_BIN"
      "NH_CLEAN_GROWTH_TIMEOUT_RUNNER_BIN"
      "NIX_STORE_GROWTH_CHECKER_BIN"
    ]
    ++ lib.optional pkgs.stdenv.hostPlatform.isLinux "NH_CLEANUP_SYSTEMD_PACKAGE";
  };
  shard = {
    testFiles = [
      "modules/features/platform/nh/_tests/nh-clean-growth-runner.bats"
      "modules/features/platform/nh/_tests/nh-cleanup-systemd.bats"
      "modules/features/platform/nh/_tests/nh-result-root-pruner.bats"
      "modules/features/platform/nh/_tests/nix-store-growth-checker.bats"
    ];
    sourceFiles = [
      "modules/features/platform/nh/_packages/cleanup-systemd/install-nh-cleanup-systemd.sh"
      "modules/features/platform/nh/_packages/clean-growth-runner/nh-clean-growth-runner.sh"
      "modules/features/platform/nh/_packages/result-root-pruner/nh-prune-result-roots.sh"
      "modules/features/platform/nh/_packages/store-growth-checker/nix-store-growth-checker.sh"
    ];
  };
}
