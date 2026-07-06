{
  description = "constantan's home-manager configuration";

  nixConfig = {
    extra-substituters = [
      "https://cache.nixos.org"
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

    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      # upstream も nixpkgs-unstable / treefmt-nix を追っており、follows で
      # root の pin に一本化する。なお lock 上の "nixpkgs" ノードは mozuku
      # 専用の古い pin (root の nixpkgs とは別物 — mozuku のコメント参照)。
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.treefmt-nix.follows = "treefmt-nix";
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
      url = "github:vercel-labs/agent-browser";
      flake = false;
    };

    agent-slack-skill = {
      url = "github:stablyai/agent-slack";
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

    # difit official agent skills (the CLI itself is packaged in nix/overlays/difit.nix).
    # バイナリ側の pin (nix/pins/difit.json) とは `nix run .#update-pins` が
    # この input ごと同期する。
    difit-src = {
      url = "github:yoshiko-pg/difit";
      flake = false;
    };

    # hcom skill source (the binary itself is packaged in nix/overlays/hcom.nix).
    # バイナリ側の pin (nix/pins/hcom.json) とは `nix run .#update-pins` が
    # この input ごと同期する。
    hcom-src = {
      url = "github:aannoo/hcom";
      flake = false;
    };

    # humanize-jp skill: suppress "AI-ness" in Japanese writing
    humanizer-jp-skill = {
      url = "github:yourbright-jp/humanizer-jp";
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

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

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

      # Nix system → 構成名・$target で使う短縮 arch 名。linuxConfigName と
      # mkLinuxHostApps の双方で使い、構成名と switch 実行時の組み立てを一致させる。
      linuxShortArch = {
        "x86_64-linux" = "x86_64";
        "aarch64-linux" = "aarch64";
      };

      linuxConfigName = { hostKind, system, ... }: "${username}@${hostKind}-${linuxShortArch.${system}}";

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

      mkCommonApps = import ./nix/lib/mk-apps.nix { inherit inputs username; };

      mkDarwinHostApps = import ./nix/lib/mk-darwin-apps.nix { inherit darwinHostname; };
      mkLinuxHostApps = import ./nix/lib/mk-linux-apps.nix {
        inherit
          inputs
          username
          windowsUsername
          windowsHomedir
          linuxShortArch
          ;
      };
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
      apps = lib.genAttrs systems (
        system:
        let
          pkgs = pkgsFor.${system};
          common = mkCommonApps {
            inherit pkgs;
            treefmtWrapper = treefmtEvalFor.${system}.config.build.wrapper;
          };
          host = if system == darwinSystem then mkDarwinHostApps pkgs else mkLinuxHostApps system pkgs;
        in
        common.apps // host.apps
      );

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
            ];
          };
        }
      );

      formatter = lib.genAttrs systems (system: treefmtEvalFor.${system}.config.build.wrapper);

      packages = lib.genAttrs systems (
        system:
        let
          pkgs = pkgsFor.${system};
        in
        {
          inherit (pkgs)
            hcom
            hcom-claude-hooks
            hcom-codex-hooks
            agent-slack
            difit
            git-wt
            herdr
            shellfirm
            herdr-agent-skill
            herdr-agent-plugin
            herdr-claude-integration
            herdr-codex-integration
            herdr-pi-integration
            herdr-opencode-integration
            herdr-codex-marketplace
            ;
        }
      );

      checks = lib.genAttrs systems (
        system:
        let
          pkgs = pkgsFor.${system};
          common = mkCommonApps {
            inherit pkgs;
            treefmtWrapper = treefmtEvalFor.${system}.config.build.wrapper;
          };
          host = if system == darwinSystem then mkDarwinHostApps pkgs else mkLinuxHostApps system pkgs;
        in
        {
          treefmt = treefmtEvalFor.${system}.config.build.check self;
          # 全 app スクリプトをビルドし、wrapper のビルド時 shellcheck を
          # CI (build-linux ジョブ) で強制する
          app-scripts = pkgs.symlinkJoin {
            name = "app-scripts";
            paths = common.scripts ++ host.scripts;
          };
          # frontmatter.nix の純関数テスト。eval 時に assert するので
          # --no-build の CI でも検知される
          frontmatter-tests =
            let
              failures = import ./nix/modules/home/agent-skills/frontmatter-tests.nix { inherit lib; };
            in
            if failures == [ ] then
              pkgs.runCommand "frontmatter-tests" { } "touch $out"
            else
              throw "frontmatter tests failed: ${builtins.toJSON failures}";
          nix-custom-settings-tests =
            let
              failures = import ./nix/lib/nix-custom-settings-tests.nix { inherit lib username; };
            in
            if failures == [ ] then
              pkgs.runCommand "nix-custom-settings-tests" { } "touch $out"
            else
              throw "nix custom settings tests failed: ${builtins.toJSON failures}";
          # Codex Python helpers のテスト。ビルド時実行なので build-linux ジョブが強制する
          merge-py-tests =
            pkgs.runCommand "merge-py-tests"
              {
                nativeBuildInputs = [
                  (pkgs.python3.withPackages (ps: [
                    ps.tomlkit
                    ps.pytest
                  ]))
                ];
              }
              ''
                cp ${./nix/modules/home/programs/codex/merge.py} merge.py
                cp ${./nix/modules/home/programs/codex/test_merge.py} test_merge.py
                cp ${./nix/modules/home/programs/codex/generate_herdr_hook_state.py} generate_herdr_hook_state.py
                cp ${./nix/modules/home/programs/codex/test_generate_herdr_hook_state.py} test_generate_herdr_hook_state.py
                pytest -q test_merge.py test_generate_herdr_hook_state.py
                touch $out
              '';
        }
        // lib.optionalAttrs (system == darwinSystem) {
          darwin-system = darwinConfigurations.${darwinHostname}.system;
        }
        // lib.listToAttrs (
          map (entry: {
            name = "home-${entry.hostKind}";
            value = homeConfigurations.${linuxConfigName entry}.activationPackage;
          }) (builtins.filter (entry: entry.system == system) linuxHostMatrix)
        )
      );
    };
}
