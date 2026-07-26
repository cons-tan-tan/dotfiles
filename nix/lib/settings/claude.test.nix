{ lib }:
let
  settingsLib = import ./claude.nix { inherit lib; };
  settings = settingsLib.mkSettings { };
  wslSettings = settingsLib.mkSettings {
    wslUserProfile = "/mnt/c/Users/test-user";
  };
in
{
  testReadOnlyFetchWrappersStayAutoApproved = {
    expr = builtins.filter (
      permission:
      builtins.elem permission [
        "Bash(gh api-get *)"
        "Bash(curl-fetch *)"
      ]
    ) settings.permissions.allow;
    expected = [
      "Bash(gh api-get *)"
      "Bash(curl-fetch *)"
    ];
  };

  testRawCurlIsNotAutoApproved = {
    expr = builtins.elem "Bash(curl *)" settings.permissions.allow;
    expected = false;
  };

  testUserProfileIsAbsentByDefault = {
    expr = settings.env ? USERPROFILE;
    expected = false;
  };

  testWslUserProfileIsSetForClaude = {
    expr = wslSettings.env.USERPROFILE;
    expected = "/mnt/c/Users/test-user";
  };
}
