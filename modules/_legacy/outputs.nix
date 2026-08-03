inputs@{
  self,
  nixpkgs,
  home-manager,
  appScriptsFor,
  ...
}:
let
  lib = nixpkgs.lib;
  username = "constantan";

  darwinSystem = "aarch64-darwin";
  darwinHomedir = "/Users/${username}";
  darwinHostname = "${username}";

  linuxHomedir = "/home/${username}";

  # Windows companion (WSL host only)
  windowsUsername = "zhouc";
  windowsHomedir = "/mnt/c/Users/${windowsUsername}";

  systems = import inputs.supported-systems;
  ciCheck = import ../../nix/lib/ci-check.nix { inherit lib; };

  mkPkgs = import ../../nix/lib/mk-pkgs.nix { inherit inputs; };

  # nixpkgs の import + overlay 適用は重いので system ごとに一度だけ行い、
  # 全出力とホスト構成で同じインスタンスを共有する。
  pkgsFor = lib.genAttrs systems mkPkgs;

  mkHost = import ../../nix/lib/mk-host.nix {
    inherit
      inputs
      username
      windowsUsername
      windowsHomedir
      pkgsFor
      ;
    homedir = linuxHomedir;
  };

  mkDarwin = import ../../nix/lib/mk-darwin.nix {
    inherit inputs username pkgsFor;
    homedir = darwinHomedir;
  };

  mkNixosWsl = import ../../nix/lib/mk-nixos-wsl.nix {
    inherit
      inputs
      username
      windowsUsername
      windowsHomedir
      pkgsFor
      ;
    homedir = linuxHomedir;
  };

  linuxHostMatrix = [
    {
      hostKind = "linux";
      system = "x86_64-linux";
      hostFile = ../../nix/hosts/linux.nix;
    }
    {
      hostKind = "linux";
      system = "aarch64-linux";
      hostFile = ../../nix/hosts/linux.nix;
    }
    {
      hostKind = "wsl";
      system = "x86_64-linux";
      hostFile = ../../nix/hosts/wsl.nix;
    }
    {
      hostKind = "wsl";
      system = "aarch64-linux";
      hostFile = ../../nix/hosts/wsl.nix;
    }
  ];

  configNames = import ../../nix/lib/linux-config-name.nix { inherit username; };
  linuxConfigName = configNames.forHost;
  nixosWslConfigName = configNames.forNixosWsl;

  nixosWslMatrix = builtins.filter (entry: entry.hostKind == "wsl") linuxHostMatrix;

  darwinConfigurations = {
    ${darwinHostname} = mkDarwin {
      system = darwinSystem;
      hostFile = ../../nix/hosts/darwin.nix;
    };
  };

  homeConfigurations = lib.listToAttrs (
    map (entry: {
      name = linuxConfigName entry;
      value = mkHost entry;
    }) linuxHostMatrix
  );

  nixosConfigurations = lib.listToAttrs (
    map (entry: {
      name = nixosWslConfigName entry;
      value = mkNixosWsl { inherit (entry) system; };
    }) nixosWslMatrix
  );

in
{
  inherit darwinConfigurations homeConfigurations nixosConfigurations;

  # CI専用gateを別定義するとlocal checksと対象が乖離するため、同じ
  # derivationから導出する。native runnerを用意していないaarch64-linuxは、
  # 実build対象へ見せかけず全system評価だけに留める。
  hydraJobs.ci = ciCheck.mkHestiaJobs {
    x86_64-linux = self.checks.x86_64-linux;
    ${darwinSystem} = self.checks.${darwinSystem};
  };

  checks = lib.genAttrs systems (
    system:
    let
      pkgs = pkgsFor.${system};
      nixosWslConfiguration =
        if lib.hasSuffix "-linux" system then
          nixosConfigurations.${nixosWslConfigName { inherit system; }}
        else
          null;
      linuxHomeConfiguration =
        if lib.hasSuffix "-linux" system then
          homeConfigurations.${
            linuxConfigName {
              hostKind = "linux";
              inherit system;
            }
          }
        else
          null;
      wslHomeConfiguration =
        if lib.hasSuffix "-linux" system then
          homeConfigurations.${
            linuxConfigName {
              hostKind = "wsl";
              inherit system;
            }
          }
        else
          null;
      baseChecks = {
        # app wrapperが別の依存から偶然buildされた時だけ検査される状態を
        # 避け、すべてのwrapperへbuild時shellcheckを適用する。
        app-scripts =
          ciCheck.annotate
            # On Darwin, keep the app closure with host configurations so
            # their shared packages are not rebuilt by a cold-cache runner.
            (ciCheck.targets.bySystem {
              darwin = "configurations";
              linux = "repo-quality";
            })
            (
              pkgs.symlinkJoin {
                name = "app-scripts";
                paths = appScriptsFor system;
              }
            );
      }
      // lib.optionalAttrs (system == "x86_64-linux") {
        den-capability-tests = ciCheck.annotate (ciCheck.targets.linux "eval-tests") (
          import ../../nix/checks/den-capabilities.nix {
            inherit inputs lib pkgs;
          }
        );
        flake-public-api-contract = ciCheck.annotate (ciCheck.targets.linux "eval-tests") (
          import ../../nix/checks/flake-public-api-contract.nix {
            inherit lib pkgs systems;
            inherit (self)
              apps
              checks
              darwinConfigurations
              devShells
              formatter
              homeConfigurations
              nixosConfigurations
              packages
              ;
            rootPackagesPresent = self ? packages;
          }
        );
        configuration-ownership-contract = ciCheck.annotate (ciCheck.targets.linux "configurations") (
          import ../../nix/checks/configuration-ownership-contract.nix {
            inherit (self)
              darwinConfigurations
              homeConfigurations
              nixosConfigurations
              ;
            inherit
              lib
              pkgs
              username
              ;
          }
        );
      }
      // ciCheck.annotateSet (ciCheck.targets.darwin "configurations") (
        lib.optionalAttrs (system == darwinSystem) {
          darwin-system = darwinConfigurations.${darwinHostname}.system;
          # hcom はデフォルト無効でも、opt-in 経路を CI で継続的に評価・build する。
          darwin-system-hcom-enabled =
            (darwinConfigurations.${darwinHostname}.extendModules {
              modules = [
                { home-manager.users.${username}.dotfiles.hcom.enable = true; }
              ];
            }).system;
          darwin-nh-cleanup-contract = import ../../nix/checks/darwin-nh-cleanup-contract.nix {
            inherit lib pkgs username;
            config = darwinConfigurations.${darwinHostname}.config;
          };
        }
      )
      // ciCheck.annotateSet (ciCheck.targets.linux "configurations") (
        lib.optionalAttrs (lib.hasSuffix "-linux" system) {
          nixos-wsl-system = nixosWslConfiguration.config.system.build.toplevel;
          nixos-wsl-tarball-builder = nixosWslConfiguration.config.system.build.tarballBuilder;
          nixos-wsl-contract = import ../../nix/checks/nixos-wsl-contract.nix {
            inherit
              lib
              linuxHomedir
              pkgs
              username
              windowsHomedir
              windowsUsername
              ;
            config = nixosWslConfiguration.config;
            sourcePath = toString self.outPath;
          };
          claude-userprofile-contract = import ../../nix/checks/claude-userprofile-contract.nix {
            inherit lib pkgs windowsHomedir;
            linuxSettings = linuxHomeConfiguration.config.home.file.".claude/settings.json".source;
            wslSettings = wslHomeConfiguration.config.home.file.".claude/settings.json".source;
          };
        }
      )
      // ciCheck.annotateSet (ciCheck.targets.linux "configurations") (
        lib.listToAttrs (
          lib.concatMap (entry: [
            {
              name = "home-${entry.hostKind}";
              value = homeConfigurations.${linuxConfigName entry}.activationPackage;
            }
            {
              name = "home-${entry.hostKind}-hcom-enabled";
              value =
                (homeConfigurations.${linuxConfigName entry}.extendModules {
                  modules = [ { dotfiles.hcom.enable = true; } ];
                }).activationPackage;
            }
          ]) (builtins.filter (entry: entry.system == system) linuxHostMatrix)
        )
      );
      testChecks = import ../../nix/tests {
        inherit
          ciCheck
          inputs
          lib
          pkgs
          username
          ;
        advisoryDb = inputs.rustsec-advisory-db;
        advisoryDbLastModified = inputs.rustsec-advisory-db.lastModified;
        flake = self;
        homeManager = home-manager;
        llmAgents = inputs.llm-agents;
        publicApps = self.apps.${system};
        reservedCheckNames = builtins.attrNames baseChecks;
      };
      allChecks = baseChecks // testChecks;
    in
    allChecks
  );
}
