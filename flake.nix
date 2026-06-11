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
      # upstream も nixpkgs-unstable を追っており、lock 上は元々同一 rev に
      # dedup されていた。follows で恒久的に一本化する。
      inputs.nixpkgs.follows = "nixpkgs";
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

    # External skill sources (deployed by nix/modules/home/agent-skills.nix)
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

    # hcom skill source (the binary itself is packaged in nix/overlays/hcom.nix).
    # NOTE: nix flake update でこの input を上げたら、nix/overlays/hcom.nix の
    # version / hash も同じタグへ手動で同期すること。
    hcom-src = {
      url = "github:aannoo/hcom";
      flake = false;
    };

    # humanize-jp skill: suppress "AI-ness" in Japanese writing
    humanizer-jp-skill = {
      url = "github:yourbright-jp/humanizer-jp";
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

      # macOS configuration
      darwinSystem = "aarch64-darwin";
      darwinHomedir = "/Users/${username}";
      darwinHostname = "${username}";

      # Linux configuration
      linuxHomedir = "/home/${username}";

      # Windows companion (WSL host only)
      windowsUsername = "zhouc";
      windowsHomedir = "/mnt/c/Users/${windowsUsername}";

      # All supported systems
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      # pkgs builder shared across hosts
      mkPkgs = import ./nix/lib/mk-pkgs.nix { inherit inputs; };

      # Home Manager configuration builder for Linux/WSL hosts
      mkHost = import ./nix/lib/mk-host.nix {
        inherit
          inputs
          username
          windowsUsername
          windowsHomedir
          ;
        homedir = linuxHomedir;
      };

      # nix-darwin configuration builder
      mkDarwin = import ./nix/lib/mk-darwin.nix {
        inherit inputs username;
        homedir = darwinHomedir;
      };

      # Linux/WSL host matrix: pair each architecture with each host kind
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

      # Homedir for Linux/WSL apps (matches mkHost)
      linuxConfigName =
        { hostKind, system, ... }:
        "${username}@${hostKind}-${
          {
            "x86_64-linux" = "x86_64";
            "aarch64-linux" = "aarch64";
          }
          .${system}
        }";

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
      mkTreefmtWrapper = pkgs: (mkTreefmtEval pkgs).config.build.wrapper;

      # 共通 apps (update / fmt / pptx / markdownlint / textlint)
      mkCommonApps = import ./nix/lib/mk-apps.nix { inherit inputs; };

      # darwin ホスト固有 apps
      mkDarwinHostApps = pkgs: {
        build = {
          type = "app";
          meta.description = "Build the nix-darwin configuration without activating it";
          program = toString (
            pkgs.writeShellScript "darwin-build" ''
              set -e
              echo "Building darwin configuration..."
              nix build .#darwinConfigurations.${darwinHostname}.system
              echo "Build successful! Run 'nix run .#switch' to apply."
            ''
          );
        };
        switch = {
          type = "app";
          meta.description = "Build and activate the nix-darwin configuration";
          program = toString (
            pkgs.writeShellScript "darwin-switch" ''
              set -e
              echo "Building and switching to darwin configuration..."
              sudo nix run nix-darwin -- switch --flake .#${darwinHostname}
            ''
          );
        };
      };

      # Linux/WSL ホスト固有 apps: switch は実行時に WSL か native Linux かを判定
      mkLinuxHostApps =
        system: pkgs:
        let
          arch =
            {
              "x86_64-linux" = "x86_64";
              "aarch64-linux" = "aarch64";
            }
            .${system};
          hmBin = "${home-manager.packages.${system}.default}/bin/home-manager";
        in
        {
          build = {
            type = "app";
            meta.description = "Build the Home Manager configuration without activating it (auto-detects WSL/Linux)";
            program = toString (
              pkgs.writeShellScript "home-manager-build" ''
                set -e
                if [[ -n "''${WSL_DISTRO_NAME:-}" ]]; then
                  target="${username}@wsl-${arch}"
                else
                  target="${username}@linux-${arch}"
                fi
                echo "Building Home Manager configuration: $target"
                nix build ".#homeConfigurations.\"$target\".activationPackage"
                echo "Build successful! Run 'nix run .#switch' to apply."
              ''
            );
          };
          switch = {
            type = "app";
            meta.description = "Build and activate the Home Manager configuration (auto-detects WSL/Linux)";
            program = toString (
              pkgs.writeShellScript "home-manager-switch" ''
                set -e
                if [[ -n "''${WSL_DISTRO_NAME:-}" ]]; then
                  target="${username}@wsl-${arch}"
                else
                  target="${username}@linux-${arch}"
                fi
                echo "Switching to Home Manager configuration: $target"
                ${hmBin} switch --flake ".#$target"
              ''
            );
          };
          winget-apply = {
            type = "app";
            meta.description = "Apply the WinGet DSC configuration on the Windows host (WSL only)";
            program = toString (
              pkgs.writeShellScript "winget-apply" ''
                set -e
                if [[ -z "''${WSL_DISTRO_NAME:-}" ]]; then
                  echo "winget-apply: not running under WSL" >&2
                  exit 1
                fi

                WIN_CONFIG="${windowsHomedir}/.config/dev.winget"
                if [ ! -f "$WIN_CONFIG" ]; then
                  echo "winget-apply: $WIN_CONFIG not found. Run 'nix run .#switch' first." >&2
                  exit 1
                fi

                WINGET_BIN=$(command -v winget.exe || true)
                if [ -z "$WINGET_BIN" ]; then
                  echo "winget-apply: winget.exe not found in PATH. Ensure WSL interop is enabled." >&2
                  exit 1
                fi

                WIN_CONFIG_PATH="C:\\Users\\${windowsUsername}\\.config\\dev.winget"
                exec "$WINGET_BIN" configure \
                  --accept-configuration-agreements \
                  -f "$WIN_CONFIG_PATH" "$@"
              ''
            );
          };
        };
      # macOS configuration with nix-darwin
      darwinConfigurations = {
        ${darwinHostname} = mkDarwin {
          system = darwinSystem;
          hostFile = ./nix/hosts/darwin.nix;
        };
      };

      # Linux/WSL configurations with standalone Home Manager
      homeConfigurations = lib.listToAttrs (
        map (entry: {
          name = linuxConfigName entry;
          value = mkHost entry;
        }) linuxHostMatrix
      );
    in
    {
      inherit darwinConfigurations homeConfigurations;

      # Apps for common tasks (全 system で同一集合を保証するため genAttrs)
      apps = lib.genAttrs systems (
        system:
        let
          pkgs = mkPkgs system;
        in
        mkCommonApps {
          inherit pkgs;
          treefmtWrapper = mkTreefmtWrapper pkgs;
        }
        // (if system == darwinSystem then mkDarwinHostApps pkgs else mkLinuxHostApps system pkgs)
      );

      # Formatter for all systems
      formatter = lib.genAttrs systems (
        system:
        let
          pkgs = mkPkgs system;
        in
        mkTreefmtWrapper pkgs
      );

      # Individual packages (e.g. `nix build .#hcom`)
      packages = lib.genAttrs systems (
        system:
        let
          pkgs = mkPkgs system;
        in
        {
          inherit (pkgs) hcom hcom-claude-hooks hcom-codex-hooks;
        }
      );

      # `nix flake check` で全ホスト構成の評価とフォーマットを検証する
      checks = lib.genAttrs systems (
        system:
        {
          treefmt = (mkTreefmtEval (mkPkgs system)).config.build.check self;
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
