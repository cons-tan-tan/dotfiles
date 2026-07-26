{
  description = "constantan's home-manager configuration";

  nixConfig = {
    extra-substituters = [
      "https://cache.nixos.org"
      # nixConfig は直接の attrset を要求して import を含む let 式を受理しないため、
      # cache-settings.nix との乖離を cache-settings-tests で検知する。
      "https://cache.numtide.com"
    ];
    extra-trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    bun2nix = {
      url = "github:nix-community/bun2nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.systems.follows = "supported-systems";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };

    hunk = {
      url = "github:modem-dev/hunk";
      inputs.bun2nix.follows = "bun2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      # upstream も nixpkgs-unstable / treefmt-nix を追っており、follows で
      # root の pin に一本化する。なお lock 上の "nixpkgs" ノードは mozuku
      # 専用の古い pin (root の nixpkgs とは別物 — mozuku のコメント参照)。
      inputs.bun2nix.follows = "bun2nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.systems.follows = "supported-systems";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };

    supported-systems = {
      url = "path:./nix/systems";
      flake = false;
    };

    rustsec-advisory-db = {
      url = "github:RustSec/advisory-db";
      flake = false;
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
    };

    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
    };

    mozuku = {
      # nixpkgs を follows しない (意図的): mozuku-lsp は cabocha / crfpp の
      # C++ チェーンごと source build になり、どのバイナリキャッシュにも無い。
      # follows にすると nixpkgs 更新の度に再ビルドが走る (実測 3 drv) ため、
      # upstream の pin のままにして再ビルドを mozuku 更新時だけに抑える。
      url = "github:t3tra-dev/MoZuKu";
    };

    codex-plugin-cc = {
      url = "github:openai/codex-plugin-cc";
      flake = false;
    };

    # External skill sources (deployed by nix/modules/home/agent-skills/)
    ast-grep-skill = {
      url = "github:ast-grep/claude-skill";
      flake = false;
    };

    agent-browser-skill = {
      url = "github:vercel-labs/agent-browser/v0.31.1";
      flake = false;
    };

    agent-slack-skill = {
      url = "github:stablyai/agent-slack/v0.9.3";
      flake = false;
    };

    anthropic-skills = {
      url = "github:anthropics/skills";
      flake = false;
    };

    drawio-skill = {
      url = "github:jgraph/drawio-mcp";
      flake = false;
    };

    # difit official agent skills (the CLI implementation is in nix/packages/difit).
    # バイナリ側の pin (nix/pins/difit.json) とは `nix run .#update-pins` が
    # この input ごと同期する。
    difit-src = {
      url = "github:yoshiko-pg/difit/v5.0.8";
      flake = false;
    };

    # hcom skill source (the CLI implementation is in nix/packages/hcom).
    # バイナリ側の pin (nix/pins/hcom.json) とは `nix run .#update-pins` が
    # この input ごと同期する。
    hcom-src = {
      url = "github:aannoo/hcom/v0.7.21";
      flake = false;
    };

    improve-skill = {
      url = "github:shadcn/improve";
      flake = false;
    };

    # Homebrew casks managed via Nix (macOS only)
    brew-nix = {
      url = "github:BatteredBunny/brew-nix";
      inputs.brew-api.follows = "brew-api";
      inputs.nix-darwin.follows = "nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    brew-api = {
      url = "github:BatteredBunny/brew-api";
      flake = false;
    };

  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      home-manager,
      treefmt-nix,
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

      mkPkgs = import ./nix/lib/mk-pkgs.nix { inherit inputs; };

      # nixpkgs の import + overlay 適用は重いので system ごとに一度だけ行い、
      # 全出力とホスト構成で同じインスタンスを共有する。
      pkgsFor = lib.genAttrs systems mkPkgs;

      mkHost = import ./nix/lib/mk-host.nix {
        inherit
          inputs
          username
          windowsUsername
          windowsHomedir
          pkgsFor
          ;
        homedir = linuxHomedir;
      };

      mkDarwin = import ./nix/lib/mk-darwin.nix {
        inherit inputs username pkgsFor;
        homedir = darwinHomedir;
      };

      mkNixosWsl = import ./nix/lib/mk-nixos-wsl.nix {
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
          hostFile = ./nix/hosts/linux.nix;
        }
        {
          hostKind = "linux";
          system = "aarch64-linux";
          hostFile = ./nix/hosts/linux.nix;
        }
        {
          hostKind = "wsl";
          system = "x86_64-linux";
          hostFile = ./nix/hosts/wsl.nix;
        }
        {
          hostKind = "wsl";
          system = "aarch64-linux";
          hostFile = ./nix/hosts/wsl.nix;
        }
      ];

      configNames = import ./nix/lib/linux-config-name.nix { inherit username; };
      linuxConfigName = configNames.forHost;
      nixosWslConfigName = configNames.forNixosWsl;

      nixosWslMatrix = builtins.filter (entry: entry.hostKind == "wsl") linuxHostMatrix;

      darwinConfigurations = {
        ${darwinHostname} = mkDarwin {
          system = darwinSystem;
          hostFile = ./nix/hosts/darwin.nix;
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

      # treefmt: formatter 出力 (wrapper) と checks 出力 (check) の両方に使う
      mkTreefmtEval =
        pkgs:
        treefmt-nix.lib.evalModule pkgs {
          projectRootFile = "flake.nix";
          programs = {
            nixfmt.enable = true;
            rustfmt.enable = true;
            shfmt.enable = true;
          };
          settings = {
            global.excludes = [
              ".git/**"
              "*.lock"
              "result"
            ];
          };
        };
      # treefmt の module 評価は重いので system ごとに 1 回だけ行い、
      # apps / formatter / checks で同じ評価を共有する
      treefmtEvalFor = lib.genAttrs systems (system: mkTreefmtEval pkgsFor.${system});

      mkCommonApps = import ./nix/lib/apps/mk-common-apps.nix { inherit inputs username; };
      appSet = import ./nix/lib/apps/mk-app-set.nix { inherit lib; };

      mkDarwinHostApps = import ./nix/lib/apps/mk-darwin-apps.nix {
        inherit inputs darwinHostname;
      };
      mkLinuxHostApps = import ./nix/lib/apps/mk-linux-apps.nix {
        inherit
          inputs
          username
          windowsHomedir
          ;
      };

      # apps と checks は同じ { apps, scripts } 束を使うため、
      # pkgsFor / treefmtEvalFor と同様に system ごとに一度だけ組み立てて共有する
      commonAppsFor = lib.genAttrs systems (
        system:
        mkCommonApps {
          pkgs = pkgsFor.${system};
          treefmtWrapper = treefmtEvalFor.${system}.config.build.wrapper;
        }
      );
      hostAppsFor = lib.genAttrs systems (
        system:
        if system == darwinSystem then
          mkDarwinHostApps {
            inherit system;
            pkgs = pkgsFor.${system};
          }
        else
          mkLinuxHostApps {
            inherit system;
            pkgs = pkgsFor.${system};
            nixosTarget = nixosWslConfigName { inherit system; };
            nixosRebuildBin = "${
              nixosConfigurations.${nixosWslConfigName { inherit system; }}.config.system.build.nixos-rebuild
            }/bin/nixos-rebuild";
          }
      );
      appsFor = lib.genAttrs systems (
        system:
        appSet.mergeAppSets [
          commonAppsFor.${system}
          hostAppsFor.${system}
        ]
      );
    in
    {
      inherit darwinConfigurations homeConfigurations nixosConfigurations;

      # 全 system で同一の app 集合になるよう genAttrs で生成する
      apps = lib.genAttrs systems (system: appsFor.${system}.apps);

      # 作業用ツール (テスト・lint・secrets 編集) の宣言的な入口。
      # 構成の build / switch には不要 — apps だけで完結する。
      devShells = lib.genAttrs systems (
        system:
        let
          pkgs = pkgsFor.${system};
          updatePinsCore = pkgs.callPackage ./nix/apps/update-pins { };
          applySecretsCore = pkgs.callPackage ./nix/apps/apply-secrets { };
          applyNixSettingsCore = pkgs.callPackage ./nix/apps/apply-nix-settings { };
          safeFetch = pkgs.callPackage ./nix/packages/safe-fetch { };
          curlFetch = pkgs.dotfilesPackages.curl-fetch;
          ghApiGet = pkgs.dotfilesPackages.gh-api-get;
        in
        {
          default = pkgs.mkShell {
            APPLY_SECRETS_TEST_BIN = lib.getExe applySecretsCore;
            APPLY_NIX_SETTINGS_TEST_BIN = lib.getExe applyNixSettingsCore;
            CURL_FETCH_PUBLIC_BIN = lib.getExe curlFetch;
            CURL_FETCH_TEST_BIN = "${safeFetch.core}/bin/curl-fetch";
            GH_API_GET_EXTENSION_ROOT = ghApiGet;
            GH_API_GET_PUBLIC_BIN = lib.getExe ghApiGet;
            GH_API_GET_TEST_BIN = "${safeFetch.core}/bin/gh-api-get";
            UPDATE_PINS_TEST_BIN = lib.getExe updatePinsCore;
            packages = with pkgs; [
              applySecretsCore
              applyNixSettingsCore
              bats
              cargo
              clippy
              ghApiGet
              shellcheck
              jq
              rustc
              rustfmt
              curlFetch
              sops
              reuse
              updatePinsCore
              yq-go
              zip
            ];
          };

          rust = pkgs.mkShell {
            packages = with pkgs; [
              cargo
              clippy
              git
              rustc
              rustfmt
            ];
          };
        }
      );

      formatter = lib.genAttrs systems (system: treefmtEvalFor.${system}.config.build.wrapper);

      checks = lib.genAttrs systems (
        system:
        let
          pkgs = pkgsFor.${system};
          nixosWslConfiguration =
            if lib.hasSuffix "-linux" system then
              nixosConfigurations.${nixosWslConfigName { inherit system; }}
            else
              null;
          baseChecks = {
            treefmt = treefmtEvalFor.${system}.config.build.check self;
            # 全 app スクリプトをビルドし、wrapper のビルド時 shellcheck を
            # CI (build-linux ジョブ) で強制する
            app-scripts = pkgs.symlinkJoin {
              name = "app-scripts";
              paths = appsFor.${system}.scripts;
            };
          }
          // lib.optionalAttrs (system == darwinSystem) {
            darwin-system = darwinConfigurations.${darwinHostname}.system;
            # hcom はデフォルト無効でも、opt-in 経路を CI で継続的に評価・build する。
            darwin-system-hcom-enabled =
              (darwinConfigurations.${darwinHostname}.extendModules {
                modules = [
                  { home-manager.users.${username}.dotfiles.hcom.enable = true; }
                ];
              }).system;
          }
          // lib.optionalAttrs (lib.hasSuffix "-linux" system) {
            nixos-wsl-system = nixosWslConfiguration.config.system.build.toplevel;
            nixos-wsl-tarball-builder = nixosWslConfiguration.config.system.build.tarballBuilder;
            nixos-wsl-contract =
              let
                cfg = nixosWslConfiguration.config;
                home = cfg.home-manager.users.${username};
                actual = {
                  wslEnabled = cfg.wsl.enable;
                  defaultUser = cfg.wsl.defaultUser;
                  interopRegistered = cfg.wsl.interop.register;
                  hasWslInteropRegistration = cfg.boot.binfmt.registrations ? WSLInterop;
                  userLinger = cfg.users.users.${username}.linger;
                  # nix/modules/nixos-wsl/default.nixの暫定対応と対になるcontract。
                  # microsoft/WSL#40519を含むreleaseで再発しないことを確認後、
                  # 対応する設定とこのattrsetを同時に削除する。
                  temporaryWslWorkarounds = {
                    hostname = {
                      configured = cfg.wsl.wslConf.network.hostname;
                      directiveGenerated = lib.hasInfix "hostname=" cfg.environment.etc."wsl.conf".text;
                    };
                    userManagerRetry = {
                      restart = cfg.systemd.services."user@".serviceConfig.Restart;
                      restartSec = cfg.systemd.services."user@".serviceConfig.RestartSec;
                      startLimitIntervalSec = cfg.systemd.services."user@".startLimitIntervalSec;
                      startLimitBurst = cfg.systemd.services."user@".startLimitBurst;
                      overrideStrategy = cfg.systemd.services."user@".overrideStrategy;
                      restartIfChanged = cfg.systemd.services."user@".restartIfChanged;
                    };
                  };
                  stateVersion = cfg.system.stateVersion;
                  flakesEnabled = lib.elem "flakes" cfg.nix.settings.experimental-features;
                  trustedUser = lib.elem username cfg.nix.settings."extra-trusted-users";
                  channelsEnabled = cfg.nix.channel.enable;
                  tarballConfigPath = toString cfg.wsl.tarball.configPath;
                  inherit (cfg.home-manager)
                    useGlobalPkgs
                    useUserPackages
                    backupFileExtension
                    ;
                  homeUsername = home.home.username;
                  homeDirectory = home.home.homeDirectory;
                  hostKind = home.my.hostKind;
                  isWsl = home.my.isWsl;
                  windowsUsername = home.my.windows.username;
                  windowsHomedir = home.my.windows.homedir;
                  dotfilesDir = home.my.dotfilesDir;
                  codexActivationAfter = home.home.activation.codexHooksConfig.after;
                };
                expected = {
                  wslEnabled = true;
                  defaultUser = username;
                  interopRegistered = true;
                  hasWslInteropRegistration = true;
                  userLinger = true;
                  temporaryWslWorkarounds = {
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
                  stateVersion = "26.05";
                  flakesEnabled = true;
                  trustedUser = true;
                  channelsEnabled = false;
                  tarballConfigPath = toString self.outPath;
                  useGlobalPkgs = true;
                  useUserPackages = true;
                  backupFileExtension = "hm-backup";
                  homeUsername = username;
                  homeDirectory = linuxHomedir;
                  hostKind = "wsl";
                  isWsl = true;
                  windowsUsername = windowsUsername;
                  windowsHomedir = windowsHomedir;
                  dotfilesDir = toString self.outPath;
                  codexActivationAfter = [ "linkGeneration" ];
                };
              in
              assert lib.assertMsg (actual == expected) ''
                NixOS-WSL configuration contract mismatch:
                expected ${builtins.toJSON expected}
                actual ${builtins.toJSON actual}
              '';
              pkgs.runCommand "nixos-wsl-contract" { } ''touch "$out"'';
          }
          // lib.listToAttrs (
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
          );
          testChecks = import ./nix/tests {
            inherit lib pkgs username;
            advisoryDb = inputs.rustsec-advisory-db;
            advisoryDbLastModified = inputs.rustsec-advisory-db.lastModified;
            homeManager = home-manager;
            publicApps = appsFor.${system}.apps;
            reservedCheckNames = builtins.attrNames baseChecks;
          };
        in
        baseChecks // testChecks
      );
    };
}
