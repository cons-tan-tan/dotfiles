{ lib, pkgs }:
let
  gpgconfFixture = pkgs.writeShellApplication {
    name = "gpgconf";
    text = ''
      : "''${TEST_TMPDIR:?}"
      echo called >>"$TEST_TMPDIR/gpgconf.log"
      printf '%s\n' /run/user/1000/gnupg/S.gpg-agent.ssh
    '';
  };
  systemctlFixture = pkgs.writeShellApplication {
    name = "systemctl";
    text = ''
      : "''${TEST_TMPDIR:?}"
      printf 'args:%s\nsocket:%s\nagent:%s\n' \
        "$*" "''${SSH_AUTH_SOCK:-}" "''${SSH_AGENT_PID:-}" \
        >"$TEST_TMPDIR/systemctl.log"
    '';
  };
  testPackage = pkgs.callPackage ../_packages/wsl-set-ssh-auth-sock {
    gpgconfBin = lib.getExe gpgconfFixture;
    systemctlBin = lib.getExe systemctlFixture;
  };
in
{
  group = "shellWrappers";
  fixture = {
    nativeBuildInputs = [ testPackage ];
    environment.GPG_WSL_AUTH_SOCK_TEST_BIN = lib.getExe testPackage;
    requiredEnvironment = [ "GPG_WSL_AUTH_SOCK_TEST_BIN" ];
  };
  shard = {
    testFiles = [ "modules/features/security/gpg/_tests/wsl-set-ssh-auth-sock.bats" ];
    sourceFiles = [ ];
  };
}
