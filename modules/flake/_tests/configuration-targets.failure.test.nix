{
  caseName,
  nixpkgsPath,
  repoRoot,
}:
let
  lib = import (nixpkgsPath + "/lib");
  configurationTargets = import (repoRoot + "/modules/flake/_interface/configuration-targets.nix") {
    inherit lib;
  };
  inherit (import (repoRoot + "/modules/flake/_tests/configuration-targets.fixture.nix"))
    den
    primaryUser
    windows
    ;
  force = value: builtins.deepSeq value true;
  resolve =
    changedDen:
    force (configurationTargets {
      den = changedDen;
      system = "x86_64-linux";
    });
  updateHome =
    name: value:
    den
    // {
      homes.x86_64-linux = den.homes.x86_64-linux // {
        ${name} = value;
      };
    };
  cases = {
    duplicateEnvironment = {
      expression = resolve (
        den
        // {
          homes.x86_64-linux = den.homes.x86_64-linux // {
            second-linux = den.homes.x86_64-linux.linux-entry // {
              intoAttr = [
                "homeConfigurations"
                "duplicate"
              ];
            };
          };
        }
      );
      expectedFragment = "standalone Linux Home Manager target requires exactly one linux entity for x86_64-linux, found 2";
    };
    missingEnvironment = {
      expression = resolve (
        den
        // {
          homes.x86_64-linux = removeAttrs den.homes.x86_64-linux [ "linux-entry" ];
        }
      );
      expectedFragment = "standalone Linux Home Manager target requires exactly one linux entity for x86_64-linux, found 0";
    };
    wrongOutputPath = {
      expression = resolve (
        den
        // {
          hosts.x86_64-linux.nixos-entry = den.hosts.x86_64-linux.nixos-entry // {
            intoAttr = [
              "homeConfigurations"
              "wrong-output"
            ];
          };
        }
      );
      expectedFragment = "must declare intoAttr = [ \"nixosConfigurations\" <non-empty-name> ]";
    };
    duplicateHomeOutput = {
      expression = resolve (
        updateHome "wsl-entry" (
          den.homes.x86_64-linux.wsl-entry
          // {
            intoAttr = den.homes.x86_64-linux.linux-entry.intoAttr;
          }
        )
      );
      expectedFragment = "must declare distinct homeConfigurations targets";
    };
    missingPrimaryHostUser = {
      expression = resolve (
        den
        // {
          hosts.x86_64-linux.nixos-entry = den.hosts.x86_64-linux.nixos-entry // {
            users.alice = primaryUser // {
              dotfiles.primary = false;
            };
          };
        }
      );
      expectedFragment = ".users requires exactly one dotfiles.primary user, found 0";
    };
    duplicatePrimaryHostUsers = {
      expression = resolve (
        den
        // {
          hosts.x86_64-linux.nixos-entry = den.hosts.x86_64-linux.nixos-entry // {
            users = den.hosts.x86_64-linux.nixos-entry.users // {
              bob = {
                userName = "bob";
                dotfiles.primary = true;
              };
            };
          };
        }
      );
      expectedFragment = ".users requires exactly one dotfiles.primary user, found 2";
    };
    standaloneHomeUserMismatch = {
      expression = resolve (
        updateHome "wsl-entry" (
          den.homes.x86_64-linux.wsl-entry
          // {
            userName = "bob";
          }
        )
      );
      expectedFragment = "standalone home userName mismatch";
    };
    hostAndStandaloneUserMismatch = {
      expression = resolve (
        den
        // {
          hosts.x86_64-linux.nixos-entry = den.hosts.x86_64-linux.nixos-entry // {
            users = {
              bob = {
                userName = "bob";
                dotfiles.primary = true;
              };
            };
          };
        }
      );
      expectedFragment = "integrated host primary userName must match standalone home userName";
    };
    explicitHomeMismatch = {
      expression = resolve (
        updateHome "linux-entry" (
          den.homes.x86_64-linux.linux-entry
          // {
            homeDirectory = "/home/bob";
          }
        )
      );
      expectedFragment = ".homeDirectory must match /home/<userName>";
    };
    missingWindowsUsername = {
      expression = resolve (
        den
        // {
          hosts.x86_64-linux.nixos-entry = den.hosts.x86_64-linux.nixos-entry // {
            dotfiles = den.hosts.x86_64-linux.nixos-entry.dotfiles // {
              windows = removeAttrs windows [ "username" ];
            };
          };
        }
      );
      expectedFragment = ".dotfiles.windows.username is required when the Windows companion is enabled";
    };
    missingWindowsHomedir = {
      expression = resolve (
        den
        // {
          hosts.x86_64-linux.nixos-entry = den.hosts.x86_64-linux.nixos-entry // {
            dotfiles = den.hosts.x86_64-linux.nixos-entry.dotfiles // {
              windows = removeAttrs windows [ "homedir" ];
            };
          };
        }
      );
      expectedFragment = ".dotfiles.windows.homedir is required when the Windows companion is enabled";
    };
    missingWslSource = {
      expression = resolve (
        den
        // {
          hosts.x86_64-linux.nixos-entry = den.hosts.x86_64-linux.nixos-entry // {
            dotfiles = removeAttrs den.hosts.x86_64-linux.nixos-entry.dotfiles [ "source" ];
          };
        }
      );
      expectedFragment = ".dotfiles.source must be a non-empty string";
    };
    windowsHomeMismatch = {
      expression = resolve (
        den
        // {
          hosts.x86_64-linux.nixos-entry = den.hosts.x86_64-linux.nixos-entry // {
            dotfiles = den.hosts.x86_64-linux.nixos-entry.dotfiles // {
              windows = windows // {
                homedir = "/mnt/c/Users/bob";
              };
            };
          };
        }
      );
      expectedFragment = ".dotfiles.windows.homedir must equal /mnt/c/Users/<dotfiles.windows.username>";
    };
    integratedWindowsIdentityMismatch = {
      expression = resolve (
        updateHome "wsl-entry" (
          den.homes.x86_64-linux.wsl-entry
          // {
            dotfiles = den.homes.x86_64-linux.wsl-entry.dotfiles // {
              windows = {
                enable = true;
                username = "bob";
                homedir = "/mnt/c/Users/bob";
              };
            };
          }
        )
      );
      expectedFragment = "integrated and standalone WSL dotfiles.windows identity must match";
    };
  };
in
if caseName == null then cases else cases.${caseName}.expression
