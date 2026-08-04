{
  config,
  den,
  inputs,
  lib,
  ...
}:
let
  username = "constantan";
  darwinSystem = "aarch64-darwin";
  linuxHomedir = "/home/${username}";
  windowsUsername = "zhouc";
  windowsHomedir = "/mnt/c/Users/${windowsUsername}";
  configNames = import ../../entities/_lib/configuration-names.nix { inherit username; };
  ciCheck = import ../../../nix/lib/ci-check.nix { inherit lib; };
in
{
  den.aspects.configuration-checks.checks =
    { pkgs, system, ... }:
    let
      inherit (config.flake)
        darwinConfigurations
        homeConfigurations
        nixosConfigurations
        ;
      homeEntries =
        map
          (hostKind: {
            inherit hostKind;
            name = configNames.forHost { inherit hostKind system; };
          })
          [
            "linux"
            "wsl"
          ];
      nixosWslConfiguration =
        if lib.hasSuffix "-linux" system then
          nixosConfigurations.${configNames.forNixosWsl { inherit system; }}
        else
          null;
      homeConfiguration =
        hostKind: homeConfigurations.${configNames.forHost { inherit hostKind system; }};
      hcomProfile =
        environment:
        import ../agents/_tests/hcom-profile.nix {
          inherit
            environment
            inputs
            lib
            system
            ;
          repoRoot = ../../..;
        };
    in
    lib.optionalAttrs (system == "x86_64-linux") {
      configuration-ownership-contract = ciCheck.annotate (ciCheck.targets.linux "configurations") (
        import ../../../nix/checks/configuration-ownership-contract.nix {
          inherit
            darwinConfigurations
            homeConfigurations
            lib
            nixosConfigurations
            pkgs
            username
            ;
        }
      );
    }
    // ciCheck.annotateSet (ciCheck.targets.darwin "configurations") (
      lib.optionalAttrs (system == darwinSystem) {
        darwin-system = darwinConfigurations.${username}.system;
        home-darwin-hcom-profile = hcomProfile "darwin";
        darwin-nh-cleanup-contract = import ../../../nix/checks/darwin-nh-cleanup-contract.nix {
          inherit lib pkgs username;
          config = darwinConfigurations.${username}.config;
        };
      }
    )
    // ciCheck.annotateSet (ciCheck.targets.linux "configurations") (
      lib.optionalAttrs (lib.hasSuffix "-linux" system) {
        nixos-wsl-system = nixosWslConfiguration.config.system.build.toplevel;
        nixos-wsl-tarball-builder = nixosWslConfiguration.config.system.build.tarballBuilder;
        nixos-wsl-contract = import ../../../nix/checks/nixos-wsl-contract.nix {
          inherit
            lib
            linuxHomedir
            pkgs
            username
            windowsHomedir
            windowsUsername
            ;
          config = nixosWslConfiguration.config;
          sourcePath = toString inputs.self.outPath;
        };
        claude-userprofile-contract = import ../../../nix/checks/claude-userprofile-contract.nix {
          inherit lib pkgs windowsHomedir;
          linuxSettings = (homeConfiguration "linux").config.home.file.".claude/settings.json".source;
          wslSettings = (homeConfiguration "wsl").config.home.file.".claude/settings.json".source;
        };
      }
    )
    // ciCheck.annotateSet (ciCheck.targets.linux "configurations") (
      lib.optionalAttrs (lib.hasSuffix "-linux" system) (
        lib.listToAttrs (
          lib.concatMap (entry: [
            {
              name = "home-${entry.hostKind}";
              value = homeConfigurations.${entry.name}.activationPackage;
            }
            {
              name = "home-${entry.hostKind}-hcom-profile";
              value = hcomProfile entry.hostKind;
            }
          ]) homeEntries
        )
      )
    );

  den.schema.flake-parts.includes = [ den.aspects.configuration-checks ];
}
