{
  lib,
  publicApps,
  subjects,
}:
{
  nativeBuildInputs = [ subjects.applyNixSettingsCore ];
  environment = {
    APPLY_NIX_SETTINGS_PUBLIC_BIN = publicApps.apply-nix-settings.program;
    APPLY_NIX_SETTINGS_TEST_BIN = lib.getExe subjects.applyNixSettingsCore;
  };
  requiredEnvironment = [
    "APPLY_NIX_SETTINGS_PUBLIC_BIN"
    "APPLY_NIX_SETTINGS_TEST_BIN"
  ];
}
