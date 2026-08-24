{
  config,
  lib,
  pkgs,
  ...
}:
let
  subjectUsername = config.wsl.defaultUser;
  subjectUid = config.users.users.${subjectUsername}.uid;
  systemSshConfig = config.environment.etc."ssh/ssh_config".text;
  systemSshConfigFile = pkgs.writeText "nixbuild-system-ssh-config" systemSshConfig;
  expectedInitScopeDropIn = ''
    [Scope]
    OOMPolicy=continue
    ManagedOOMPreference=omit
    MemoryHigh=24G
    MemoryMax=28G
    MemorySwapMax=4G
  '';

  contracts = {
    "nixbuild-ssh-agent" = {
      actual = config.systemd.services.nix-daemon.environment.SSH_AUTH_SOCK;
      expected = "/run/user/${toString subjectUid}/gnupg/S.gpg-agent.ssh";
    };

    "memory-pressure-protection" = {
      actual = {
        oomd = {
          enabled = config.systemd.oomd.enable;
          rootMemoryPressureEnabled = config.systemd.oomd.enableRootSlice;
          rootSwapAction = config.systemd.slices."-".sliceConfig.ManagedOOMSwap;
          swapUsedLimit = config.systemd.oomd.settings.OOM.SwapUsedLimit;
          userSlicesEnabled = config.systemd.oomd.enableUserSlices;
        };
        userSlice = {
          inherit (config.systemd.slices.user.sliceConfig)
            MemoryAccounting
            MemoryHigh
            MemoryMax
            MemorySwapMax
            ;
        };
        initScope = {
          enabled = config.systemd.units."init.scope".enable;
          overrideStrategy = config.systemd.units."init.scope".overrideStrategy;
          dropIn = config.systemd.units."init.scope".text;
        };
        nixDaemon = {
          inherit (config.systemd.services.nix-daemon.serviceConfig)
            MemoryAccounting
            MemoryHigh
            MemoryMax
            MemorySwapMax
            ;
        };
      };
      expected = {
        oomd = {
          enabled = true;
          rootMemoryPressureEnabled = false;
          rootSwapAction = "kill";
          swapUsedLimit = "80%";
          userSlicesEnabled = true;
        };
        userSlice = {
          MemoryAccounting = true;
          MemoryHigh = "24G";
          MemoryMax = "28G";
          MemorySwapMax = "4G";
        };
        initScope = {
          enabled = true;
          overrideStrategy = "asDropin";
          dropIn = expectedInitScopeDropIn;
        };
        nixDaemon = {
          MemoryAccounting = true;
          MemoryHigh = "20G";
          MemoryMax = "24G";
          MemorySwapMax = "4G";
        };
      };
    };

    # modules/features/platform/wsl/base.nixの暫定対応と対になるcontract。
    # microsoft/WSL#40519を含むreleaseで再発しないことを確認後、
    # 対応する設定とこのcontractを同時に削除する。
    "temporary-wsl-workarounds" = {
      actual = {
        hostname = {
          configured = config.wsl.wslConf.network.hostname;
          directiveGenerated = lib.hasInfix "hostname=" config.environment.etc."wsl.conf".text;
        };
        userManagerRetry = {
          restart = config.systemd.services."user@".serviceConfig.Restart;
          restartSec = config.systemd.services."user@".serviceConfig.RestartSec;
          startLimitIntervalSec = config.systemd.services."user@".startLimitIntervalSec;
          startLimitBurst = config.systemd.services."user@".startLimitBurst;
          overrideStrategy = config.systemd.services."user@".overrideStrategy;
          restartIfChanged = config.systemd.services."user@".restartIfChanged;
        };
      };
      expected = {
        hostname = {
          configured = "";
          directiveGenerated = false;
        };
        userManagerRetry = {
          restart = "on-failure";
          restartSec = "250ms";
          startLimitIntervalSec = 5;
          startLimitBurst = 5;
          overrideStrategy = "asDropinIfExists";
          restartIfChanged = false;
        };
      };
    };
  };

  failures = lib.filterAttrs (_: contract: contract.actual != contract.expected) contracts;
in
assert lib.assertMsg (failures == { }) ''
  NixOS-WSL configuration contract mismatches:
  ${builtins.toJSON failures}
'';
pkgs.runCommand "nixos-wsl-contract"
  {
    nativeBuildInputs = [
      pkgs.openssh
      pkgs.ripgrep
    ];
  }
  ''
    # Included store files appear as owned by nobody inside the build sandbox,
    # which OpenSSH rejects. Preserve the final config order while omitting
    # unrelated Include directives from this effective-value check.
    rg --invert-match '^[[:space:]]*Include[[:space:]]' ${systemSshConfigFile} > ssh-config-under-test
    ssh -G -F ssh-config-under-test eu.nixbuild.net 2>/dev/null > effective-ssh-config
    rg --quiet --line-regexp 'pubkeyacceptedalgorithms ssh-ed25519' effective-ssh-config
    rg --quiet --line-regexp 'serveraliveinterval 60' effective-ssh-config
    rg --quiet --line-regexp 'ipqos none none' effective-ssh-config
    touch "$out"
  ''
