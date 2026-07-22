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

    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hunk = {
      url = "github:modem-dev/hunk";
      inputs.bun2nix.inputs.systems.follows = "supported-systems";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      # upstream も nixpkgs-unstable / treefmt-nix を追っており、follows で
      # root の pin に一本化する。なお lock 上の "nixpkgs" ノードは mozuku
      # 専用の古い pin (root の nixpkgs とは別物 — mozuku のコメント参照)。
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.systems.follows = "supported-systems";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };

    supported-systems = {
      url = "path:./nix/systems";
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
      url = "github:yoshiko-pg/difit/v5.0.4";
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

      # treefmt: formatter 出力 (wrapper) と checks 出力 (check) の両方に使う
      mkTreefmtEval =
        pkgs:
        treefmt-nix.lib.evalModule pkgs {
          projectRootFile = "flake.nix";
          programs = {
            nixfmt.enable = true;
            shfmt.enable = true;
            ruff-format.enable = true;
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

      mkDarwinHostApps = import ./nix/lib/apps/mk-darwin-apps.nix { inherit darwinHostname; };
      mkLinuxHostApps = import ./nix/lib/apps/mk-linux-apps.nix {
        inherit
          inputs
          username
          windowsUsername
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
          mkDarwinHostApps { pkgs = pkgsFor.${system}; }
        else
          mkLinuxHostApps {
            inherit system;
            pkgs = pkgsFor.${system};
          }
      );
      appsFor = lib.genAttrs systems (
        system:
        appSet.mergeAppSets [
          commonAppsFor.${system}
          hostAppsFor.${system}
        ]
      );
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
    in
    {
      inherit darwinConfigurations homeConfigurations;

      # 全 system で同一の app 集合になるよう genAttrs で生成する
      apps = lib.genAttrs systems (system: appsFor.${system}.apps);

      # 作業用ツール (テスト・lint・secrets 編集) の宣言的な入口。
      # 構成の build / switch には不要 — apps だけで完結する。
      devShells = lib.genAttrs systems (
        system:
        let
          pkgs = pkgsFor.${system};
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              bats
              shellcheck
              jq
              sops
              reuse
              (python3.withPackages (ps: [
                ps.pytest
                ps.tomlkit
              ]))
            ];
          };
        }
      );

      formatter = lib.genAttrs systems (system: treefmtEvalFor.${system}.config.build.wrapper);

      checks = lib.genAttrs systems (
        system:
        let
          pkgs = pkgsFor.${system};
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
            reservedCheckNames = builtins.attrNames baseChecks;
          };
        in
        baseChecks // testChecks
      );
    };
}
