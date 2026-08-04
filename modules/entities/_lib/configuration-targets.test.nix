{ lib }:
let
  configurationTargets = import ./configuration-targets.nix { inherit lib; };
  evaluationSucceeds = value: (builtins.tryEval (builtins.deepSeq value true)).success;
  den = {
    hosts = {
      aarch64-darwin.laptop = {
        dotfiles.environment = "darwin";
        intoAttr = [
          "darwinConfigurations"
          "workstation"
        ];
      };
      x86_64-linux.nixos-entry = {
        dotfiles.environment = "wsl";
        intoAttr = [
          "nixosConfigurations"
          "wsl-primary"
        ];
      };
    };
    homes.x86_64-linux = {
      linux-entry = {
        dotfiles.environment = "linux";
        intoAttr = [
          "homeConfigurations"
          "alice@linux"
        ];
      };
      wsl-entry = {
        dotfiles.environment = "wsl";
        intoAttr = [
          "homeConfigurations"
          "alice@wsl"
        ];
      };
    };
  };
in
{
  testDarwinTargetComesFromEntityIntoAttr = {
    expr =
      (configurationTargets {
        inherit den;
        system = "aarch64-darwin";
      }).darwin;
    expected = "workstation";
  };

  testDarwinEntityNameComesFromEnvironment = {
    expr =
      (configurationTargets {
        inherit den;
        system = "aarch64-darwin";
      }).entityNames.darwin;
    expected = "laptop";
  };

  testLinuxTargetsComeFromEntityEnvironmentAndIntoAttr = {
    expr = configurationTargets {
      inherit den;
      system = "x86_64-linux";
    };
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
    };
  };

  testDuplicateEnvironmentEntitiesAreRejected = {
    expr = evaluationSucceeds (configurationTargets {
      system = "x86_64-linux";
      den = den // {
        homes.x86_64-linux = den.homes.x86_64-linux // {
          second-linux = {
            dotfiles.environment = "linux";
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

  testWrongOutputPathIsRejected = {
    expr = evaluationSucceeds (configurationTargets {
      system = "x86_64-linux";
      den = den // {
        hosts.x86_64-linux = den.hosts.x86_64-linux // {
          nixos-entry = den.hosts.x86_64-linux.nixos-entry // {
            intoAttr = [
              "homeConfigurations"
              "wrong-output"
            ];
          };
        };
      };
    });
    expected = false;
  };

  testDuplicateHomeOutputTargetsAreRejected = {
    expr = evaluationSucceeds (configurationTargets {
      system = "x86_64-linux";
      den = den // {
        homes.x86_64-linux = den.homes.x86_64-linux // {
          wsl-entry = den.homes.x86_64-linux.wsl-entry // {
            intoAttr = den.homes.x86_64-linux.linux-entry.intoAttr;
          };
        };
      };
    });
    expected = false;
  };
}
