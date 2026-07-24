{
  awscli2,
  configHelper,
  lib,
  loginConfigFile,
  writeShellApplication,
}:
writeShellApplication {
  name = "aws-login";
  text = ''
    AWS_CONFIG_HELPER_BIN=${lib.escapeShellArg (lib.getExe configHelper)}
    AWS_LOGIN_AWS_BIN=${lib.escapeShellArg (lib.getExe awscli2)}
    AWS_LOGIN_BASE_CONFIG=${lib.escapeShellArg loginConfigFile}
    ${builtins.readFile ./aws-login.sh}
  '';
}
