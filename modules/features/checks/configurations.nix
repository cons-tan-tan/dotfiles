{
  config,
  den,
  lib,
  ...
}:
let
  darwinSystem = "aarch64-darwin";
  configurationTargets = import ../../flake/_interface/configuration-targets.nix { inherit lib; };
  ciCheck = import ../ci/_interface/check.nix { inherit lib; };
  checkContext =
    { pkgs, system }:
    let
      targets = configurationTargets { inherit den system; };
      inherit (config.flake)
        darwinConfigurations
        homeConfigurations
        nixosConfigurations
        ;
      homeConfiguration = environment: homeConfigurations.${targets.home.${environment}};
    in
    {
      inherit
        darwinConfigurations
        homeConfiguration
        homeConfigurations
        nixosConfigurations
        pkgs
        system
        targets
        ;
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
      homeEntries = lib.mapAttrsToList (environment: name: {
        hostKind = environment;
        inherit name;
      }) targets.home;
      nixosWslConfiguration =
        if lib.hasSuffix "-linux" system then nixosConfigurations.${targets.nixosWsl} else null;
    };
  evaluationCompleteChecks =
    { pkgs, system }:
    let
      context = checkContext { inherit pkgs system; };
      inherit (context)
        darwinConfigurations
        entityContexts
        homeConfiguration
        homeConfigurations
        nixosConfigurations
        nixosWslConfiguration
        targets
        username
        ;
    in
    lib.optionalAttrs (system == "x86_64-linux") {
      configuration-ownership-contract = import ./_tests/configuration-ownership-contract.nix {
        inherit
          darwinConfigurations
          entityContexts
          homeConfigurations
          lib
          nixosConfigurations
          pkgs
          ;
      };
    }
    // lib.optionalAttrs (system == darwinSystem) {
      darwin-nh-cleanup-contract = import ../platform/nh/_tests/darwin-cleanup-contract.nix {
        inherit lib pkgs username;
        config = darwinConfigurations.${targets.darwin}.config;
      };
    }
    // lib.optionalAttrs (lib.hasSuffix "-linux" system) {
      nixos-wsl-contract =
        let
          platformContract = import ../platform/wsl/_tests/nixos-contract.nix {
            inherit lib pkgs;
            entityContext = targets;
            config = nixosWslConfiguration.config;
          };
          nhNixosCleanupContract = import ../platform/nh/_tests/nixos-cleanup-contract.nix {
            inherit lib pkgs;
            entityContext = targets;
            config = nixosWslConfiguration.config;
          };
          nhHomeCleanupContract = import ../platform/nh/_tests/home-cleanup-contract.nix {
            inherit lib pkgs;
            linux = homeConfiguration "linux";
            wsl = homeConfiguration "wsl";
          };
        in
        pkgs.linkFarm "nixos-wsl-contract" [
          {
            name = "platform";
            path = platformContract;
          }
          {
            name = "nh-cleanup";
            path = nhNixosCleanupContract;
          }
          {
            name = "nh-home-cleanup";
            path = nhHomeCleanupContract;
          }
        ];
    };
  buildComposition =
    { pkgs, system }:
    let
      context = checkContext { inherit pkgs system; };
      inherit (context)
        darwinConfigurations
        homeConfigurations
        homeEntries
        nixosWslConfiguration
        targets
        username
        ;
      hcomProfile =
        homeConfiguration: import ../agents/hcom/_tests/profile-check.nix { inherit homeConfiguration; };
      darwinChecks = lib.optionalAttrs (system == darwinSystem) {
        darwin-system = darwinConfigurations.${targets.darwin}.system;
        home-darwin-hcom-profile =
          (darwinConfigurations.${targets.darwin}.extendModules {
            modules = [
              { home-manager.users.${username}.dotfiles.hcom.enable = true; }
            ];
          }).system;
      };
      linuxChecks =
        lib.optionalAttrs (lib.hasSuffix "-linux" system) {
          nixos-wsl-system = nixosWslConfiguration.config.system.build.toplevel;
          nixos-wsl-tarball-builder = nixosWslConfiguration.config.system.build.tarballBuilder;
          claude-userprofile-contract = import ../agents/claude/_tests/userprofile-contract.nix {
            inherit lib pkgs;
            expectedUserProfile = targets.contexts.home.wsl.windows.homedir;
            linuxSettings =
              homeConfigurations.${targets.home.linux}.config.home.file.".claude/settings.json".source;
            wslSettings =
              homeConfigurations.${targets.home.wsl}.config.home.file.".claude/settings.json".source;
          };
        }
        // lib.optionalAttrs (lib.hasSuffix "-linux" system) (
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
        );
    in
    ciCheck.composeBuildProducers {
      producers = [
        (ciCheck.mkBuildProducer {
          owner = "Darwin configuration checks";
          entries = ciCheck.buildEntrySet (ciCheck.targets.darwin "configurations") darwinChecks;
        })
        (ciCheck.mkBuildProducer {
          owner = "Linux configuration checks";
          entries = ciCheck.buildEntrySet (ciCheck.targets.linux "configurations") linuxChecks;
        })
      ];
    };
in
{
  imports = [ ../ci/_interface/options.nix ];

  perSystem =
    { pkgs, system, ... }:
    {
      dotfiles.ci.evaluationCompleteCheckProducers = [
        {
          owner = "configuration checks";
          checks = evaluationCompleteChecks { inherit pkgs system; };
        }
      ];
      dotfiles.ci.buildRouteProducers = [
        {
          owner = "configuration checks";
          routes = (buildComposition { inherit pkgs system; }).routes;
        }
      ];
    };

  den.aspects.configuration-checks.checks =
    { pkgs, system, ... }:
    (buildComposition { inherit pkgs system; }).checks;

  den.schema.flake-parts.includes = [ den.aspects.configuration-checks ];
}
