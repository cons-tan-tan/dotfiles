{ lib }:
let
  commandPolicyInterface = import ../../base/_interface/command-policy.nix;
  evaluatedPolicy = lib.evalModules {
    modules = [
      commandPolicyInterface.options
      commandPolicyInterface.rules
    ];
  };
  policy = evaluatedPolicy.config.agentCommandPolicy;
  commandPolicy = commandPolicyInterface.compiler {
    inherit lib;
    inherit (policy)
      commands
      shell
      shellfirm
      ;
  };
  settingsLib = import ../_lib/settings.nix { inherit lib commandPolicy; };
  settings = settingsLib.mkSettings { };
  wslSettings = settingsLib.mkSettings {
    wslUserProfile = "/mnt/c/Users/test-user";
  };
  windowsSettings = settingsLib.mkSettings { forWindows = true; };
  guardedSettings = settingsLib.mkSettings { guardCommand = "/store/guard --policy /store/policy"; };
  guardedWindowsSettings = settingsLib.mkSettings {
    forWindows = true;
    guardCommand = "/store/guard --policy /store/policy";
  };
in
{
  testConfiguredFetchCommandsStayAutoApproved = {
    expr = lib.sort builtins.lessThan (
      builtins.filter (
        permission:
        builtins.elem permission [
          "Bash(gh api-get *)"
          "Bash(curl-fetch *)"
          "Bash(ax *)"
        ]
      ) settings.permissions.allow
    );
    expected = [
      "Bash(ax *)"
      "Bash(gh api-get *)"
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

  testGuardHookIsPosixOnlyAndKeepsTheExactCommand = {
    expr = {
      posix = guardedSettings.hooks.PreToolUse;
      windows = guardedWindowsSettings.hooks.PreToolUse;
    };
    expected = {
      posix = [
        {
          matcher = "Bash";
          hooks = [
            {
              type = "command";
              command = "/store/guard --policy /store/policy";
              timeout = 10;
            }
          ];
        }
      ];
      windows = [ ];
    };
  };
}
