{
  fixture = {
    nativeBuildInputs = [ ];
    environment = { };
    requiredEnvironment = [ ];
  };
  shard = {
    testFiles = [ "modules/features/security/gpg/_tests/wsl-set-ssh-auth-sock.bats" ];
    sourceFiles = [
      "modules/features/security/gpg/_packages/wsl-set-ssh-auth-sock/set-ssh-auth-sock.sh"
    ];
  };
}
