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
  configurationTargets = import ../../entities/_lib/configuration-targets.nix { inherit lib; };
  ciCheck = import ../../../nix/lib/ci-check.nix { inherit lib; };
in
{
  den.aspects.configuration-checks.checks =
    { pkgs, system, ... }:
    let
      targets = configurationTargets { inherit den system; };
      inherit (config.flake)
        darwinConfigurations
        homeConfigurations
        nixosConfigurations
        ;
      homeEntries = lib.mapAttrsToList (environment: name: {
        hostKind = environment;
        inherit name;
      }) targets.home;
      nixosWslConfiguration =
        if lib.hasSuffix "-linux" system then nixosConfigurations.${targets.nixosWsl} else null;
      homeConfiguration = environment: homeConfigurations.${targets.home.${environment}};
      hcomProfile =
        homeConfiguration: import ../agents/_tests/hcom-profile.nix { inherit homeConfiguration; };
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
        darwin-system = darwinConfigurations.${targets.darwin}.system;
        home-darwin-hcom-profile =
          (darwinConfigurations.${targets.darwin}.extendModules {
            modules = [
              { home-manager.users.${username}.dotfiles.hcom.enable = true; }
            ];
          }).system;
        darwin-nh-cleanup-contract = import ../../../nix/checks/darwin-nh-cleanup-contract.nix {
          inherit lib pkgs username;
          config = darwinConfigurations.${targets.darwin}.config;
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
              value = hcomProfile homeConfigurations.${entry.name};
            }
          ]) homeEntries
        )
      )
    );

  den.schema.flake-parts.includes = [ den.aspects.configuration-checks ];
}
