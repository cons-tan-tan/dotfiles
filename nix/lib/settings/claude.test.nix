{ lib }:
let
  settingsLib = import ./claude.nix { inherit lib; };
  settings = settingsLib.mkSettings { };
  wslSettings = settingsLib.mkSettings {
    wslUserProfile = "/mnt/c/Users/test-user";
  };
  windowsSettings = settingsLib.mkSettings { forWindows = true; };
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

  testFdOptionPolicyDoesNotUseLossyClaudeGlobs = {
    expr = lib.any (lib.hasPrefix "Bash(fd ") settings.permissions.deny;
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

  testWindowsDoesNotReceiveCommandPolicy = {
    expr = {
      hasBashAllow = lib.any (lib.hasPrefix "Bash(") windowsSettings.permissions.allow;
      hasCommandPolicyDeny = windowsSettings.permissions ? deny;
    };
    expected = {
      hasBashAllow = false;
      hasCommandPolicyDeny = false;
    };
  };
}
