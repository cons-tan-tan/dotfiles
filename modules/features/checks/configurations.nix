{
  config,
  den,
  inputs,
  lib,
  ...
}:
let
  darwinSystem = "aarch64-darwin";
  configurationTargets = import ../../flake/_interface/configuration-targets.nix { inherit lib; };
  ciCheck = import ../ci/_interface/check.nix { inherit lib; };
in
{
  perSystem =
    { system, ... }:
    {
      dotfiles.ci.evaluationCompleteCheckNames =
        lib.optionals (system == "x86_64-linux") [ "configuration-ownership-contract" ]
        ++ lib.optionals (system == darwinSystem) [ "darwin-nh-cleanup-contract" ]
        ++ lib.optionals (lib.hasSuffix "-linux" system) [ "nixos-wsl-contract" ];
    };

  den.aspects.configuration-checks.checks =
    { pkgs, system, ... }:
    let
      targets = configurationTargets { inherit den system; };
      username = targets.username;
      entityContexts = {
        darwin = configurationTargets {
          inherit den;
          system = "aarch64-darwin";
        };
        linuxX86 = configurationTargets {
          inherit den;
          system = "x86_64-linux";
        };
        linuxAarch64 = configurationTargets {
          inherit den;
          system = "aarch64-linux";
        };
      };
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
        homeConfiguration: import ../agents/hcom/_tests/profile-check.nix { inherit homeConfiguration; };
    in
    lib.optionalAttrs (system == "x86_64-linux") {
      configuration-ownership-contract = ciCheck.evaluationComplete (
        import ./_tests/configuration-ownership-contract.nix {
          inherit
            darwinConfigurations
            entityContexts
            homeConfigurations
            lib
            nixosConfigurations
            pkgs
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
      }
    )
    // lib.optionalAttrs (system == darwinSystem) {
      darwin-nh-cleanup-contract = ciCheck.evaluationComplete (
        import ../platform/nh/_tests/darwin-cleanup-contract.nix {
          inherit lib pkgs username;
          config = darwinConfigurations.${targets.darwin}.config;
        }
      );
    }
    // ciCheck.annotateSet (ciCheck.targets.linux "configurations") (
      lib.optionalAttrs (lib.hasSuffix "-linux" system) {
        nixos-wsl-system = nixosWslConfiguration.config.system.build.toplevel;
        nixos-wsl-tarball-builder = nixosWslConfiguration.config.system.build.tarballBuilder;
        claude-userprofile-contract = import ../agents/claude/_tests/userprofile-contract.nix {
          inherit lib pkgs;
          linuxSettings = (homeConfiguration "linux").config.home.file.".claude/settings.json".source;
          wslSettings = (homeConfiguration "wsl").config.home.file.".claude/settings.json".source;
        };
      }
    )
    // lib.optionalAttrs (lib.hasSuffix "-linux" system) {
      nixos-wsl-contract = ciCheck.evaluationComplete (
        import ../platform/wsl/_tests/nixos-contract.nix {
          inherit
            lib
            pkgs
            ;
          entityContext = targets;
          config = nixosWslConfiguration.config;
          sourcePath = toString inputs.self.outPath;
        }
      );
    }
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
