{
  awscli2,
  coreutils,
  crudini,
  lib,
  loginConfigFile,
  writeShellApplication,
}:
writeShellApplication {
  name = "aws-login";
  runtimeInputs = [
    awscli2
    coreutils
    crudini
  ];
  text = ''
    AWS_LOGIN_BASE_CONFIG=${lib.escapeShellArg loginConfigFile}
    ${builtins.readFile ./aws-login.sh}
  '';
}
