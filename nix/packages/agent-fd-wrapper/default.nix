{
  fd,
  lib,
  writeText,
  writeShellApplication,
}:
let
  # POSIX の Claude/Codex package wrapper から共用する。Windows companion は
  # 共通command policyの対象外で、このwrapperも導入しない。
  commandPolicy = import ../../lib/agent-command-policy { inherit lib; };
  forbiddenOptions = writeText "agent-fd-forbidden-options" (
    lib.concatStringsSep "\n" commandPolicy.fdForbiddenOptions + "\n"
  );
in
writeShellApplication {
  name = "fd";
  text = ''
    FD_BIN=${lib.escapeShellArg (lib.getExe fd)}
    FD_FORBIDDEN_OPTIONS=${forbiddenOptions}
    ${builtins.readFile ./fd-wrapper.sh}
  '';
}
