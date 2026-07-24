{
  configHelper,
  baselineFile,
  lib,
  managedSections,
  writeShellApplication,
}:
assert managedSections != [ ];
writeShellApplication {
  name = "aws-config-reconcile";
  text = ''
    config_file="$HOME/.aws/config"
    exec ${lib.escapeShellArg (lib.getExe configHelper)} reconcile \
      --baseline ${lib.escapeShellArg baselineFile} \
      --target "$config_file" \
      ${lib.concatMapStringsSep " \\\n      " (
        section: "--managed-section ${lib.escapeShellArg section}"
      ) managedSections}
  '';
}
