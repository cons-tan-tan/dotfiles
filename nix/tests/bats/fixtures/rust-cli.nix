{
  lib,
  publicApps,
  subjects,
}:
{
  nativeBuildInputs = [
    subjects.applyNixSettingsCore
    subjects.applySecretsCore
  ];
  environment = {
    APPLY_NIX_SETTINGS_PUBLIC_BIN = publicApps.apply-nix-settings.program;
    APPLY_NIX_SETTINGS_TEST_BIN = lib.getExe subjects.applyNixSettingsCore;
    APPLY_SECRETS_PUBLIC_BIN = publicApps.apply-secrets.program;
    APPLY_SECRETS_TEST_BIN = lib.getExe subjects.applySecretsCore;
  };
  requiredEnvironment = [
    "APPLY_NIX_SETTINGS_PUBLIC_BIN"
    "APPLY_NIX_SETTINGS_TEST_BIN"
    "APPLY_SECRETS_PUBLIC_BIN"
    "APPLY_SECRETS_TEST_BIN"
  ];
}
