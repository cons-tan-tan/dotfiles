{ lib }:
let
  configurationTargets = import ../_interface/configuration-targets.nix { inherit lib; };
  inherit (import ./configuration-targets.fixture.nix) den windows;
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
        homedir = "/Users/alice";
        environment = "darwin";
        source = "/Users/alice/source";
        standalone = false;
        system = "aarch64-darwin";
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
          standalone = false;
          system = "x86_64-linux";
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
            standalone = true;
            system = "x86_64-linux";
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
            standalone = true;
            system = "x86_64-linux";
            inherit windows;
          };
        };
      };
    };
  };

}
