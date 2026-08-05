{
  checker,
  cleanupArguments ? [ ],
  cleanupCommand,
  coreutils,
  lib,
  maximumAgeSeconds,
  queryTimeout,
  retryIntervalSeconds,
  storePath ? "/nix/store",
  thresholdBytes,
  writeShellApplication,
}:
writeShellApplication {
  name = "nh-clean-growth-runner";
  runtimeInputs = [ coreutils ];

  text = ''
    readonly growth_checker=${lib.escapeShellArg (lib.getExe checker)}
    readonly cleanup_command=(${lib.escapeShellArgs ([ cleanupCommand ] ++ cleanupArguments)})
    readonly query_timeout=${lib.escapeShellArg queryTimeout}
    readonly maximum_age_seconds=${lib.escapeShellArg (toString maximumAgeSeconds)}
    readonly retry_interval_seconds=${lib.escapeShellArg (toString retryIntervalSeconds)}
    readonly store_path=${lib.escapeShellArg storePath}
    readonly threshold_bytes=${lib.escapeShellArg (toString thresholdBytes)}

    ${builtins.readFile ./nh-clean-growth-runner.sh}
  '';
}
