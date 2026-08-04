{ lib }:
let
  configurationTargets = import ./configuration-targets.nix { inherit lib; };
  evaluationSucceeds = value: (builtins.tryEval (builtins.deepSeq value true)).success;
  windows = {
    enable = true;
    username = "alice-win";
    homedir = "/mnt/c/Users/alice-win";
  };
  primaryUser = {
    userName = "alice";
    dotfiles.primary = true;
  };
  den = {
    hosts = {
      aarch64-darwin.laptop = {
        dotfiles = {
          environment = "darwin";
          source = "/Users/alice/source";
        };
        intoAttr = [
          "darwinConfigurations"
          "workstation"
        ];
        users.alice = primaryUser;
      };
      x86_64-linux.nixos-entry = {
        dotfiles = {
          environment = "wsl";
          source = "/nix/store/wsl-source";
          inherit windows;
        };
        intoAttr = [
          "nixosConfigurations"
          "wsl-primary"
        ];
        users.alice = primaryUser;
      };
    };
    homes.x86_64-linux = {
      linux-entry = {
        userName = "alice";
        dotfiles = {
          environment = "linux";
          source = "/home/alice/source";
        };
        intoAttr = [
          "homeConfigurations"
          "alice@linux"
        ];
      };
      wsl-entry = {
        userName = "alice";
        dotfiles = {
          environment = "wsl";
          source = "/home/alice/source";
          inherit windows;
        };
        intoAttr = [
          "homeConfigurations"
          "alice@wsl"
        ];
      };
    };
  };
  linuxContext = configurationTargets {
    inherit den;
    system = "x86_64-linux";
  };
in
{
  testDarwinTargetAndIdentityComeFromEntity = {
    expr = configurationTargets {
      inherit den;
      system = "aarch64-darwin";
    };
    expected = {
      darwin = "workstation";
      entityNames.darwin = "laptop";
      username = "alice";
      windows = {
        enable = false;
        username = null;
        homedir = null;
      };
      contexts.darwin = {
        entityName = "laptop";
        outputName = "workstation";
        username = "alice";
        environment = "darwin";
        source = "/Users/alice/source";
        windows = {
          enable = false;
          username = null;
          homedir = null;
        };
      };
    };
  };

  testLinuxTargetsAndIdentityComeFromEntities = {
    expr = linuxContext;
    expected = {
      nixosWsl = "wsl-primary";
      home = {
        linux = "alice@linux";
        wsl = "alice@wsl";
      };
      entityNames = {
        nixosWsl = "nixos-entry";
        home = {
          linux = "linux-entry";
          wsl = "wsl-entry";
        };
      };
      username = "alice";
      linuxHomedir = "/home/alice";
      inherit windows;
      contexts = {
        nixosWsl = {
          entityName = "nixos-entry";
          outputName = "wsl-primary";
          username = "alice";
          homedir = "/home/alice";
          environment = "wsl";
          source = "/nix/store/wsl-source";
          inherit windows;
        };
        home = {
          linux = {
            entityName = "linux-entry";
            outputName = "alice@linux";
            userName = "alice";
            homedir = "/home/alice";
            environment = "linux";
            source = "/home/alice/source";
            windows = {
              enable = false;
              username = null;
              homedir = null;
            };
          };
          wsl = {
            entityName = "wsl-entry";
            outputName = "alice@wsl";
            userName = "alice";
            homedir = "/home/alice";
            environment = "wsl";
            source = "/home/alice/source";
            inherit windows;
          };
        };
      };
    };
  };

  testDuplicateEnvironmentEntitiesAreRejected = {
    expr = evaluationSucceeds (configurationTargets {
      system = "x86_64-linux";
      den = den // {
        homes.x86_64-linux = den.homes.x86_64-linux // {
          second-linux = den.homes.x86_64-linux.linux-entry // {
            intoAttr = [
              "homeConfigurations"
              "duplicate"
            ];
          };
        };
      };
    });
    expected = false;
  };

  testMissingEnvironmentEntityIsRejected = {
    expr = evaluationSucceeds (configurationTargets {
      system = "x86_64-linux";
      den = den // {
        homes.x86_64-linux = removeAttrs den.homes.x86_64-linux [ "linux-entry" ];
      };
    });
    expected = false;
  };

  testWrongOutputPathIsRejected = {
    expr = evaluationSucceeds (configurationTargets {
      system = "x86_64-linux";
      den = den // {
        hosts.x86_64-linux.nixos-entry = den.hosts.x86_64-linux.nixos-entry // {
          intoAttr = [
            "homeConfigurations"
            "wrong-output"
          ];
        };
      };
    });
    expected = false;
  };

  testDuplicateHomeOutputTargetsAreRejected = {
    expr = evaluationSucceeds (configurationTargets {
      system = "x86_64-linux";
      den = den // {
        homes.x86_64-linux.wsl-entry = den.homes.x86_64-linux.wsl-entry // {
          intoAttr = den.homes.x86_64-linux.linux-entry.intoAttr;
        };
      };
    });
    expected = false;
  };

  testMissingPrimaryHostUserIsRejected = {
    expr = evaluationSucceeds (configurationTargets {
      system = "x86_64-linux";
      den = den // {
        hosts.x86_64-linux.nixos-entry = den.hosts.x86_64-linux.nixos-entry // {
          users.alice = primaryUser // {
            dotfiles.primary = false;
          };
        };
      };
    });
    expected = false;
  };

  testDuplicatePrimaryHostUsersAreRejected = {
    expr = evaluationSucceeds (configurationTargets {
      system = "x86_64-linux";
      den = den // {
        hosts.x86_64-linux.nixos-entry = den.hosts.x86_64-linux.nixos-entry // {
          users = den.hosts.x86_64-linux.nixos-entry.users // {
            bob = {
              userName = "bob";
              dotfiles.primary = true;
            };
          };
        };
      };
    });
    expected = false;
  };

  testStandaloneHomeUserMismatchIsRejected = {
    expr = evaluationSucceeds (configurationTargets {
      system = "x86_64-linux";
      den = den // {
        homes.x86_64-linux.wsl-entry = den.homes.x86_64-linux.wsl-entry // {
          userName = "bob";
        };
      };
    });
    expected = false;
  };

  testHostAndStandaloneUserMismatchIsRejected = {
    expr = evaluationSucceeds (configurationTargets {
      system = "x86_64-linux";
      den = den // {
        hosts.x86_64-linux.nixos-entry = den.hosts.x86_64-linux.nixos-entry // {
          users = {
            bob = {
              userName = "bob";
              dotfiles.primary = true;
            };
          };
        };
      };
    });
    expected = false;
  };

  testExplicitHomeMustMatchUserName = {
    expr = evaluationSucceeds (configurationTargets {
      system = "x86_64-linux";
      den = den // {
        homes.x86_64-linux.linux-entry = den.homes.x86_64-linux.linux-entry // {
          homeDirectory = "/home/bob";
        };
      };
    });
    expected = false;
  };

  testMissingWindowsUsernameIsRejected = {
    expr = evaluationSucceeds (configurationTargets {
      system = "x86_64-linux";
      den = den // {
        hosts.x86_64-linux.nixos-entry = den.hosts.x86_64-linux.nixos-entry // {
          dotfiles = den.hosts.x86_64-linux.nixos-entry.dotfiles // {
            windows = removeAttrs windows [ "username" ];
          };
        };
      };
    });
    expected = false;
  };

  testMissingWindowsHomedirIsRejected = {
    expr = evaluationSucceeds (configurationTargets {
      system = "x86_64-linux";
      den = den // {
        hosts.x86_64-linux.nixos-entry = den.hosts.x86_64-linux.nixos-entry // {
          dotfiles = den.hosts.x86_64-linux.nixos-entry.dotfiles // {
            windows = removeAttrs windows [ "homedir" ];
          };
        };
      };
    });
    expected = false;
  };

  testMissingWslSourceIsRejected = {
    expr = evaluationSucceeds (configurationTargets {
      system = "x86_64-linux";
      den = den // {
        hosts.x86_64-linux.nixos-entry = den.hosts.x86_64-linux.nixos-entry // {
          dotfiles = removeAttrs den.hosts.x86_64-linux.nixos-entry.dotfiles [ "source" ];
        };
      };
    });
    expected = false;
  };

  testWindowsHomeMustMatchUsername = {
    expr = evaluationSucceeds (configurationTargets {
      system = "x86_64-linux";
      den = den // {
        hosts.x86_64-linux.nixos-entry = den.hosts.x86_64-linux.nixos-entry // {
          dotfiles = den.hosts.x86_64-linux.nixos-entry.dotfiles // {
            windows = windows // {
              homedir = "/mnt/c/Users/bob";
            };
          };
        };
      };
    });
    expected = false;
  };

  testIntegratedAndStandaloneWindowsIdentityMustMatch = {
    expr = evaluationSucceeds (configurationTargets {
      system = "x86_64-linux";
      den = den // {
        homes.x86_64-linux.wsl-entry = den.homes.x86_64-linux.wsl-entry // {
          dotfiles = den.homes.x86_64-linux.wsl-entry.dotfiles // {
            windows = {
              enable = true;
              username = "bob";
              homedir = "/mnt/c/Users/bob";
            };
          };
        };
      };
    });
    expected = false;
  };
}
