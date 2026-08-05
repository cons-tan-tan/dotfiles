{
  lib,
  publicApps,
  subjects,
}:
{
  nativeBuildInputs = [ subjects.applySecretsCore ];
  environment = {
    APPLY_SECRETS_PUBLIC_BIN = publicApps.apply-secrets.program;
    APPLY_SECRETS_TEST_BIN = lib.getExe subjects.applySecretsCore;
  };
  requiredEnvironment = [
    "APPLY_SECRETS_PUBLIC_BIN"
    "APPLY_SECRETS_TEST_BIN"
  ];
}
